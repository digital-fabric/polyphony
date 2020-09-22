#ifdef POLYPHONY_BACKEND_LIBURING

#include <netdb.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "polyphony.h"
#include "../liburing/liburing.h"
#include "ruby/thread.h"

#include <poll.h>
#include <sys/types.h>
#include <sys/eventfd.h>

#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434   /* System call # on most architectures */
#endif

static int pidfd_open(pid_t pid, unsigned int flags) {
  return syscall(__NR_pidfd_open, pid, flags);
}

VALUE cTCPSocket;

typedef struct Backend_t {
  struct  io_uring ring;
  int     running;
  int     ref_count;
  int     run_no_wait_count;
} Backend_t;

#include "backend_common.h"

typedef struct sqe_context {
  VALUE         fiber;
  __s32         result;
} sqe_context_t;

static size_t Backend_size(const void *ptr) {
  return sizeof(Backend_t);
}

static const rb_data_type_t Backend_type = {
    "IOUringBackend",
    {0, 0, Backend_size,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE Backend_allocate(VALUE klass) {
  Backend_t *backend = ALLOC(Backend_t);

  return TypedData_Wrap_Struct(klass, &Backend_type, backend);
}

#define GetBackend(obj, backend) \
  TypedData_Get_Struct((obj), Backend_t, &Backend_type, (backend))

static VALUE Backend_initialize(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  io_uring_queue_init(100, &backend->ring, 0); // TODO: dynamic queue depth

  backend->running = 0;
  backend->ref_count = 0;
  backend->run_no_wait_count = 0;

  return Qnil;
}

VALUE Backend_finalize(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  io_uring_queue_exit(&backend->ring);
  return self;
}

VALUE Backend_post_fork(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  io_uring_queue_exit(&backend->ring);  
  io_uring_queue_init(100, &backend->ring, 0); // TODO: dynamic queue depth

  return self;
}

VALUE Backend_ref(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  backend->ref_count++;
  return self;
}

VALUE Backend_unref(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  backend->ref_count--;
  return self;
}

int Backend_ref_count(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  return backend->ref_count;
}

void Backend_reset_ref_count(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  backend->ref_count = 0;
}

VALUE Backend_pending_count(VALUE self) {
  return INT2NUM(0);
}

void *io_uring_backend_poll(void *ptr) {
  struct io_uring *ring = (struct io_uring *)ptr;
  struct io_uring_cqe *cqe;
  int ret = io_uring_wait_cqe(ring, &cqe);
  if (ret < 0) return 0;

  sqe_context_t *ctx = io_uring_cqe_get_data(cqe);
  if (ctx) {
    ctx->result = cqe->res;
    Fiber_make_runnable(ctx->fiber, Qnil);
  }
  io_uring_cqe_seen(ring, cqe);
  return 0;
}

VALUE Backend_poll(VALUE self, VALUE nowait, VALUE current_fiber, VALUE runqueue) {
  int is_nowait = nowait == Qtrue;
  Backend_t *backend;
  GetBackend(self, backend);

  if (is_nowait) {
    backend->run_no_wait_count++;
    if (backend->run_no_wait_count < 10) return self;

    long runnable_count = Runqueue_len(runqueue);
    if (backend->run_no_wait_count < runnable_count) return self;
  }

  backend->run_no_wait_count = 0;

  COND_TRACE(2, SYM_backend_poll_enter, current_fiber);
  backend->running = 1;
  rb_thread_call_without_gvl(io_uring_backend_poll, (void *)&backend->ring, RUBY_UBF_IO, 0);
  backend->running = 0;
  COND_TRACE(2, SYM_backend_poll_leave, current_fiber);
  
  return self;
}

VALUE Backend_wakeup(VALUE self) {
  // TODO: wakeup from io_uring polling, we'll perhaps use eventfd for each ring:
  //  - use io_uring_prep_poll_add on the fd and submit sqe
  //  - associate a special user data value, which signifies a wakeup event
  //  - when io_uring_wait_cqe returns, if user data is a wakeup event,
  //    - read from event fd
  //    - resubmit sqe for event fd

  Backend_t *backend;
  GetBackend(self, backend);

  if (backend->running) {
    // Since the loop will run until at least one event has occurred, we signal
    // the selector's associated async watcher, which will cause the ev loop to
    // return. In contrast to using `ev_break` to break out of the loop, which
    // should be called from the same thread (from within the ev_loop), using an
    // `ev_async` allows us to interrupt the event loop across threads.
    
    // ev_async_send(backend->ev_loop, &backend->break_async);
    
    return Qtrue;
  }

  return Qnil;
}

VALUE io_uring_backend_submit_and_await(Backend_t *backend, struct io_uring_sqe *sqe, sqe_context_t *ctx, int raise_exception) {
  VALUE switchpoint_result = Qnil;

  io_uring_sqe_set_data(sqe, ctx);
  io_uring_submit(&backend->ring);
  
  switchpoint_result = backend_await(backend);
  
  if (TEST_EXCEPTION(switchpoint_result)) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_cancel(sqe, ctx, 0);
    io_uring_submit(&backend->ring);
    if (raise_exception) RAISE_EXCEPTION(switchpoint_result);
  }
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

VALUE io_uring_backend_wait_fd(Backend_t *backend, int fd, int write, int raise_exception) {
  sqe_context_t ctx;
  ctx.fiber = rb_fiber_current();

  struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
  io_uring_prep_poll_add(sqe, fd, write ? POLLOUT : POLLIN);
  return io_uring_backend_submit_and_await(backend, sqe, &ctx, raise_exception);
}

VALUE Backend_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof) {
  rb_raise(rb_eRuntimeError, "Not implemented");
  return self;
}

VALUE Backend_read_loop(VALUE self, VALUE io) {
  rb_raise(rb_eRuntimeError, "Not implemented");
  return self;
}

VALUE Backend_writev(VALUE self, VALUE io, int argc, VALUE *argv) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_io;
  long total_length = 0;
  long total_written = 0;
  struct iovec *iov = 0;
  struct iovec *iov_ptr = 0;
  int iov_count = argc;
  sqe_context_t ctx;
  ctx.fiber = rb_fiber_current();

  underlying_io = rb_iv_get(io, "@io");
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);

  iov = malloc(iov_count * sizeof(struct iovec));
  for (int i = 0; i < argc; i++) {
    VALUE str = argv[i];
    iov[i].iov_base = StringValuePtr(str);
    iov[i].iov_len = RSTRING_LEN(str);
    total_length += iov[i].iov_len;
  }
  iov_ptr = iov;

  while (1) {
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_writev(sqe, fptr->fd, iov_ptr, iov_count, -1);
    switchpoint_result = io_uring_backend_submit_and_await(backend, sqe, &ctx, 0);
    if (TEST_EXCEPTION(switchpoint_result)) goto error;

    ssize_t n = ctx.result;
    if (n < 0) {
      free(iov);
      rb_syserr_fail(n, strerror(n));
    }
    else {
      total_written += n;
      if (total_written == total_length) break;

      while (n > 0) {
        if ((size_t) n < iov_ptr[0].iov_len) {
          iov_ptr[0].iov_base = (char *) iov_ptr[0].iov_base + n;
          iov_ptr[0].iov_len -= n;
          n = 0;
        }
        else {
          n -= iov_ptr[0].iov_len;
          iov_ptr += 1;
          iov_count -= 1;
        }
      }
    }
  }

  RB_GC_GUARD(ctx.fiber);
  RB_GC_GUARD(switchpoint_result);

  free(iov);
  return INT2NUM(total_written);
error:
  free(iov);
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_write_m(int argc, VALUE *argv, VALUE self) {
  if (argc < 2)
    // TODO: raise ArgumentError
    rb_raise(rb_eRuntimeError, "(wrong number of arguments (expected 2 or more))");

  return Backend_writev(self, argv[0], argc - 1, argv + 1);
}

///////////////////////////////////////////////////////////////////////////

VALUE Backend_accept(VALUE self, VALUE sock) {
  rb_raise(rb_eRuntimeError, "Not implemented");
  return self;
}

VALUE Backend_accept_loop(VALUE self, VALUE sock) {
  rb_raise(rb_eRuntimeError, "Not implemented");
  return self;
}

VALUE Backend_connect(VALUE self, VALUE sock, VALUE host, VALUE port) {
  rb_raise(rb_eRuntimeError, "Not implemented");
  return self;
}

VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io = rb_iv_get(io, "@io");
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  GetOpenFile(io, fptr);

  return io_uring_backend_wait_fd(backend, fptr->fd, RTEST(write), 1);
}

VALUE Backend_sleep(VALUE self, VALUE duration) {
  Backend_t *backend;
  sqe_context_t ctx;
  ctx.fiber = rb_fiber_current();
  struct io_uring_sqe *sqe;
  double duration_integral;
  double duration_fraction = modf(NUM2DBL(duration), &duration_integral);
  struct __kernel_timespec ts;

  GetBackend(self, backend);
  sqe = io_uring_get_sqe(&backend->ring);
  ts.tv_sec = duration_integral;
	ts.tv_nsec = floor(duration_fraction * 1000000000);
  
  io_uring_prep_timeout(sqe, &ts, 0, 0);
  return io_uring_backend_submit_and_await(backend, sqe, &ctx, 1);
}

VALUE Backend_waitpid(VALUE self, VALUE pid) {
  Backend_t *backend;
  VALUE switchpoint_result;
  int fd = pidfd_open(NUM2INT(pid), 0);
  GetBackend(self, backend);
  
  switchpoint_result = io_uring_backend_wait_fd(backend, fd, 0, 0);
  close(fd);

  TEST_RESUME_EXCEPTION(switchpoint_result);
  return self;
}

VALUE Backend_wait_event(VALUE self, VALUE raise) {
  Backend_t *backend;
  VALUE switchpoint_result;
  int fd = eventfd(0, 0);
  GetBackend(self, backend);

  switchpoint_result = io_uring_backend_wait_fd(backend, fd, 0, 0);
  close(fd);

  TEST_RESUME_EXCEPTION(switchpoint_result);
  return self;
}

void Init_Backend() {
  rb_require("socket");
  cTCPSocket = rb_const_get(rb_cObject, rb_intern("TCPSocket"));

  VALUE cBackend = rb_define_class_under(mPolyphony, "Backend", rb_cData);
  rb_define_alloc_func(cBackend, Backend_allocate);

  rb_define_method(cBackend, "initialize", Backend_initialize, 0);
  rb_define_method(cBackend, "finalize", Backend_finalize, 0);
  rb_define_method(cBackend, "post_fork", Backend_post_fork, 0);
  rb_define_method(cBackend, "pending_count", Backend_pending_count, 0);

  rb_define_method(cBackend, "ref", Backend_ref, 0);
  rb_define_method(cBackend, "unref", Backend_unref, 0);

  rb_define_method(cBackend, "poll", Backend_poll, 3);
  rb_define_method(cBackend, "break", Backend_wakeup, 0);

  rb_define_method(cBackend, "read", Backend_read, 4);
  rb_define_method(cBackend, "read_loop", Backend_read_loop, 1);
  rb_define_method(cBackend, "write", Backend_write_m, -1);
  rb_define_method(cBackend, "accept", Backend_accept, 1);
  rb_define_method(cBackend, "accept_loop", Backend_accept_loop, 1);
  rb_define_method(cBackend, "connect", Backend_connect, 3);
  rb_define_method(cBackend, "wait_io", Backend_wait_io, 2);
  rb_define_method(cBackend, "sleep", Backend_sleep, 1);
  rb_define_method(cBackend, "waitpid", Backend_waitpid, 1);
  rb_define_method(cBackend, "wait_event", Backend_wait_event, 1);

  ID_ivar_is_nonblocking = rb_intern("@is_nonblocking"); // declared in backend_common.c

  __BACKEND__.pending_count   = Backend_pending_count;
  __BACKEND__.poll            = Backend_poll;
  __BACKEND__.ref             = Backend_ref;
  __BACKEND__.ref_count       = Backend_ref_count;
  __BACKEND__.reset_ref_count = Backend_reset_ref_count;
  __BACKEND__.unref           = Backend_unref;
  __BACKEND__.wait_event      = Backend_wait_event;
  __BACKEND__.wakeup          = Backend_wakeup;
}

#endif // POLYPHONY_BACKEND_LIBURING
