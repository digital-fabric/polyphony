#ifdef POLYPHONY_BACKEND_LIBURING

#include <netdb.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdnoreturn.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/eventfd.h>
#include <sys/wait.h>
#include <errno.h>

#include "polyphony.h"
#include "../liburing/liburing.h"
#include "backend_io_uring_context.h"
#include "ruby/thread.h"
#include "ruby/io.h"

VALUE SYM_io_uring;

#ifdef POLYPHONY_UNSET_NONBLOCK
ID ID_ivar_is_nonblocking;

// One of the changes introduced in Ruby 3.0 as part of the work on the
// FiberScheduler interface is that all created sockets are marked as
// non-blocking. This prevents the io_uring backend from working correctly,
// since it will return an EAGAIN error just like a normal syscall. So here
// instead of setting O_NONBLOCK (which is required for the libev backend), we
// unset it.
inline void io_unset_nonblock(rb_io_t *fptr, VALUE io) {
  VALUE is_nonblocking = rb_ivar_get(io, ID_ivar_is_nonblocking);
  if (is_nonblocking == Qfalse) return;

  rb_ivar_set(io, ID_ivar_is_nonblocking, Qfalse);

  int oflags = fcntl(fptr->fd, F_GETFL);
  if ((oflags == -1) && (oflags & O_NONBLOCK)) return;
  oflags &= !O_NONBLOCK;
  fcntl(fptr->fd, F_SETFL, oflags);
}
#else
#define io_unset_nonblock(fptr, io)
#endif

typedef struct Backend_t {
  // common fields
  unsigned int        currently_polling;
  unsigned int        pending_count;
  unsigned int        poll_no_wait_count;

  // implementation-specific fields
  struct io_uring     ring;
  op_context_store_t  store;
  unsigned int        pending_sqes;
  unsigned int        prepared_limit;
  int                 event_fd;
} Backend_t;

#include "backend_common.h"

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

  backend->currently_polling = 0;
  backend->pending_count = 0;
  backend->poll_no_wait_count = 0;
  backend->pending_sqes = 0;
  backend->prepared_limit = 2048;

  context_store_initialize(&backend->store);
  io_uring_queue_init(backend->prepared_limit, &backend->ring, 0);
  backend->event_fd = -1;

  return Qnil;
}

VALUE Backend_finalize(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  io_uring_queue_exit(&backend->ring);
  if (backend->event_fd != -1) close(backend->event_fd);
  context_store_free(&backend->store);
  return self;
}

VALUE Backend_post_fork(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  io_uring_queue_exit(&backend->ring);
  io_uring_queue_init(backend->prepared_limit, &backend->ring, 0);
  context_store_free(&backend->store);
  backend->currently_polling = 0;
  backend->pending_count = 0;
  backend->poll_no_wait_count = 0;
  backend->pending_sqes = 0;

  return self;
}

unsigned int Backend_pending_count(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  return backend->pending_count;
}

typedef struct poll_context {
  struct io_uring     *ring;
  struct io_uring_cqe *cqe;
  int                 result;
} poll_context_t;

extern int __sys_io_uring_enter(int fd, unsigned to_submit, unsigned min_complete, unsigned flags, sigset_t *sig);

void *io_uring_backend_poll_without_gvl(void *ptr) {
  poll_context_t *ctx = (poll_context_t *)ptr;
  ctx->result = io_uring_wait_cqe(ctx->ring, &ctx->cqe);
  return NULL;
}

// copied from queue.c
static inline bool cq_ring_needs_flush(struct io_uring *ring) {
	return IO_URING_READ_ONCE(*ring->sq.kflags) & IORING_SQ_CQ_OVERFLOW;
}

void io_uring_backend_handle_completion(struct io_uring_cqe *cqe, Backend_t *backend) {
  op_context_t *ctx = io_uring_cqe_get_data(cqe);
  if (!ctx) return;

  ctx->result = cqe->res;

  if (ctx->completed)
    // already marked as deleted as result of fiber resuming before op
    // completion, so we can release the context
    context_store_release(&backend->store, ctx);
  else {
    // otherwise, we mark it as completed, schedule the fiber and let it deal
    // with releasing the context
    ctx->completed = 1;
    if (ctx->result != -ECANCELED) Fiber_make_runnable(ctx->fiber, ctx->resume_value);
  }
}

// adapted from io_uring_peek_batch_cqe in queue.c 
// this peeks at cqes and for each one 
void io_uring_backend_handle_ready_cqes(Backend_t *backend) {
  struct io_uring *ring = &backend->ring;
	bool overflow_checked = false;
  struct io_uring_cqe *cqe;
	unsigned head;
  unsigned cqe_count;

again:
  cqe_count = 0;
  io_uring_for_each_cqe(ring, head, cqe) {
    ++cqe_count;
    io_uring_backend_handle_completion(cqe, backend);
  }
  io_uring_cq_advance(ring, cqe_count);

	if (overflow_checked) goto done;

	if (cq_ring_needs_flush(ring)) {
		__sys_io_uring_enter(ring->ring_fd, 0, 0, IORING_ENTER_GETEVENTS, NULL);
		overflow_checked = true;
		goto again;
	}

done:
	return;
}

void io_uring_backend_poll(Backend_t *backend) {
  poll_context_t poll_ctx;
  poll_ctx.ring = &backend->ring;
  if (backend->pending_sqes) {
    backend->pending_sqes = 0;
    io_uring_submit(&backend->ring);
  }

  backend->currently_polling = 1;
  rb_thread_call_without_gvl(io_uring_backend_poll_without_gvl, (void *)&poll_ctx, RUBY_UBF_IO, 0);
  backend->currently_polling = 0;
  if (poll_ctx.result < 0) return;

  io_uring_backend_handle_completion(poll_ctx.cqe, backend);
  io_uring_cqe_seen(&backend->ring, poll_ctx.cqe);
}

VALUE Backend_poll(VALUE self, VALUE nowait, VALUE current_fiber, VALUE runqueue) {
  int is_nowait = nowait == Qtrue;
  Backend_t *backend;
  GetBackend(self, backend);

  if (is_nowait) {
    backend->poll_no_wait_count++;
    if (backend->poll_no_wait_count < 10) return self;

    long runnable_count = Runqueue_len(runqueue);
    if (backend->poll_no_wait_count < runnable_count) return self;
  }

  backend->poll_no_wait_count = 0;

  if (is_nowait && backend->pending_sqes) {
    backend->pending_sqes = 0;
    io_uring_submit(&backend->ring);
  }

  COND_TRACE(2, SYM_fiber_event_poll_enter, current_fiber);
  if (!is_nowait) io_uring_backend_poll(backend);
  io_uring_backend_handle_ready_cqes(backend);
  COND_TRACE(2, SYM_fiber_event_poll_leave, current_fiber);
  
  return self;
}

VALUE Backend_wakeup(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  if (backend->currently_polling) {
    // Since we're currently blocking while waiting for a completion, we add a
    // NOP which would cause the io_uring_enter syscall to return
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_nop(sqe);
    backend->pending_sqes = 0;
    io_uring_submit(&backend->ring);
    
    return Qtrue;
  }

  return Qnil;
}

inline void io_uring_backend_defer_submit(Backend_t *backend) {
  backend->pending_sqes += 1;
  if (backend->pending_sqes >= backend->prepared_limit) {
    backend->pending_sqes = 0;
    io_uring_submit(&backend->ring);
  }
}

int io_uring_backend_defer_submit_and_await(
  Backend_t *backend,
  struct io_uring_sqe *sqe,
  op_context_t *ctx,
  VALUE *value_ptr
)
{
  VALUE switchpoint_result = Qnil;

  io_uring_sqe_set_data(sqe, ctx);
  io_uring_sqe_set_flags(sqe, IOSQE_ASYNC);
  io_uring_backend_defer_submit(backend);

  switchpoint_result = backend_await(backend);

  if (!ctx->completed) {
    ctx->result = -ECANCELED;

    // op was not completed, so we need to cancel it
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_cancel(sqe, ctx, 0);
    backend->pending_sqes = 0;
    io_uring_submit(&backend->ring);
  }

  if (value_ptr) (*value_ptr) = switchpoint_result;
  RB_GC_GUARD(switchpoint_result);
  RB_GC_GUARD(ctx->fiber);
  return ctx->result;
}

VALUE io_uring_backend_wait_fd(Backend_t *backend, int fd, int write) {
  op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_POLL);
  VALUE resumed_value = Qnil;

  struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
  io_uring_prep_poll_add(sqe, fd, write ? POLLOUT : POLLIN);

  io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resumed_value);
  RB_GC_GUARD(resumed_value);
  return resumed_value;
}

VALUE Backend_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof) {
  Backend_t *backend;
  rb_io_t *fptr;
  long dynamic_len = length == Qnil;
  long len = dynamic_len ? 4096 : NUM2INT(length);
  int shrinkable = io_setstrbuf(&str, len);
  char *buf = RSTRING_PTR(str);
  long total = 0;
  int read_to_eof = RTEST(to_eof);
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_unset_nonblock(fptr, io);
  rectify_io_file_pos(fptr);
  OBJ_TAINT(str);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_READ);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_read(sqe, fptr->fd, buf, len - total, -1);

    int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else if (!result)
      break; // EOF
    else {
      total += result;
      if (!read_to_eof) break;

      if (total == len) {
        if (!dynamic_len) break;

        rb_str_resize(str, total);
        rb_str_modify_expand(str, len);
        buf = RSTRING_PTR(str) + total;
        shrinkable = 0;
        len += len;
      }
      else buf += result;
    }
  }

  io_set_read_length(str, total, shrinkable);
  io_enc_str(str, fptr);

  if (!total) return Qnil;

  return str;
}

VALUE Backend_read_loop(VALUE self, VALUE io) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE str;
  long total;
  long len = 8192;
  int shrinkable;
  char *buf;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_unset_nonblock(fptr, io);
  rectify_io_file_pos(fptr);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_READ);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_read(sqe, fptr->fd, buf, len, -1);
    
    ssize_t result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else if (!result)
      break; // EOF
    else {
      total = result;
      READ_LOOP_YIELD_STR();
    }
  }

  RB_GC_GUARD(str);

  return io;
}

VALUE Backend_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE str;
  long total;
  long len = 8192;
  int shrinkable;
  char *buf;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);
  ID method_id = SYM2ID(method);

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_unset_nonblock(fptr, io);
  rectify_io_file_pos(fptr);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_READ);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_read(sqe, fptr->fd, buf, len, -1);
    
    ssize_t result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else if (!result)
      break; // EOF
    else {
      total = result;
      READ_LOOP_PASS_STR_TO_RECEIVER(receiver, method_id);
    }
  }

  RB_GC_GUARD(str);

  return io;
}

VALUE Backend_write(VALUE self, VALUE io, VALUE str) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io;

  underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);
  io_unset_nonblock(fptr, io);

  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;

  while (left > 0) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_WRITE);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_write(sqe, fptr->fd, buf, left, -1);
    
    int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);
    
    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else {
      buf += result;
      left -= result;
    }
  }

  return INT2NUM(len);
}

VALUE Backend_writev(VALUE self, VALUE io, int argc, VALUE *argv) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io;
  long total_length = 0;
  long total_written = 0;
  struct iovec *iov = 0;
  struct iovec *iov_ptr = 0;
  int iov_count = argc;

  underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);
  io_unset_nonblock(fptr, io);

  iov = malloc(iov_count * sizeof(struct iovec));
  for (int i = 0; i < argc; i++) {
    VALUE str = argv[i];
    iov[i].iov_base = StringValuePtr(str);
    iov[i].iov_len = RSTRING_LEN(str);
    total_length += iov[i].iov_len;
  }
  iov_ptr = iov;

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_WRITEV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_writev(sqe, fptr->fd, iov_ptr, iov_count, -1);
    
    int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    if (TEST_EXCEPTION(resume_value)) {
      free(iov);
      RAISE_EXCEPTION(resume_value);
    }
    if (!ctx->completed) {
      free(iov);
      return resume_value;
    }
    RB_GC_GUARD(resume_value);

    if (result < 0) {
      free(iov);
      rb_syserr_fail(-result, strerror(-result));
    }
    else {
      total_written += result;
      if (total_written >= total_length) break;

      while (result > 0) {
        if ((size_t) result < iov_ptr[0].iov_len) {
          iov_ptr[0].iov_base = (char *) iov_ptr[0].iov_base + result;
          iov_ptr[0].iov_len -= result;
          result = 0;
        }
        else {
          result -= iov_ptr[0].iov_len;
          iov_ptr += 1;
          iov_count -= 1;
        }
      }
    }
  }

  free(iov);
  return INT2NUM(total_written);
}

VALUE Backend_write_m(int argc, VALUE *argv, VALUE self) {
  if (argc < 2)
    // TODO: raise ArgumentError
    rb_raise(rb_eRuntimeError, "(wrong number of arguments (expected 2 or more))");

  return (argc == 2) ?
    Backend_write(self, argv[0], argv[1]) :
    Backend_writev(self, argv[0], argc - 1, argv + 1);
}

VALUE Backend_recv(VALUE self, VALUE io, VALUE str, VALUE length) {
  Backend_t *backend;
  rb_io_t *fptr;
  long dynamic_len = length == Qnil;
  long len = dynamic_len ? 4096 : NUM2INT(length);
  int shrinkable = io_setstrbuf(&str, len);
  char *buf = RSTRING_PTR(str);
  long total = 0;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_unset_nonblock(fptr, io);
  rectify_io_file_pos(fptr);
  OBJ_TAINT(str);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_RECV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_recv(sqe, fptr->fd, buf, len - total, 0);
    
    int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else {
      total += result;
      break;
    }
  }

  io_set_read_length(str, total, shrinkable);
  io_enc_str(str, fptr);

  if (!total) return Qnil;

  return str;
}

VALUE Backend_recv_loop(VALUE self, VALUE io) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE str;
  long total;
  long len = 8192;
  int shrinkable;
  char *buf;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_unset_nonblock(fptr, io);
  rectify_io_file_pos(fptr);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_RECV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_recv(sqe, fptr->fd, buf, len, 0);
    
    int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else if (!result)
      break; // EOF
    else {
      total = result;
      READ_LOOP_YIELD_STR();
    }
  }

  RB_GC_GUARD(str);
  return io;
}

VALUE Backend_recv_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE str;
  long total;
  long len = 8192;
  int shrinkable;
  char *buf;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);
  ID method_id = SYM2ID(method);

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_unset_nonblock(fptr, io);
  rectify_io_file_pos(fptr);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_RECV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_recv(sqe, fptr->fd, buf, len, 0);
    
    int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else if (!result)
      break; // EOF
    else {
      total = result;
      READ_LOOP_PASS_STR_TO_RECEIVER(receiver, method_id);
    }
  }

  RB_GC_GUARD(str);
  return io;
}

VALUE Backend_send(VALUE self, VALUE io, VALUE str) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io;

  underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);
  io_unset_nonblock(fptr, io);

  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;

  while (left > 0) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_SEND);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_send(sqe, fptr->fd, buf, left, 0);
    
    int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (result < 0)
      rb_syserr_fail(-result, strerror(-result));
    else {
      buf += result;
      left -= result;
    }
  }

  return INT2NUM(len);
}

VALUE io_uring_backend_accept(Backend_t *backend, VALUE server_socket, VALUE socket_class, int loop) {
  rb_io_t *fptr;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE socket = Qnil;
  VALUE underlying_sock = rb_ivar_get(server_socket, ID_ivar_io);
  if (underlying_sock != Qnil) server_socket = underlying_sock;

  GetOpenFile(server_socket, fptr);
  io_unset_nonblock(fptr, server_socket);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_ACCEPT);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_accept(sqe, fptr->fd, &addr, &len, 0);
    
    int fd = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    if (!ctx->completed) return resume_value;
    RB_GC_GUARD(resume_value);

    if (fd < 0)
      rb_syserr_fail(-fd, strerror(-fd));
    else {
      rb_io_t *fp;

      socket = rb_obj_alloc(socket_class);
      MakeOpenFile(socket, fp);
      rb_update_max_fd(fd);
      fp->fd = fd;
      fp->mode = FMODE_READWRITE | FMODE_DUPLEX;
      rb_io_ascii8bit_binmode(socket);
      rb_io_synchronized(fp);

      // if (rsock_do_not_reverse_lookup) {
	    //   fp->mode |= FMODE_NOREVLOOKUP;
      // }
      if (loop) {
        rb_yield(socket);
        socket = Qnil;
      }
      else
        return socket;
    }
  }
  RB_GC_GUARD(socket);
  return Qnil;
}

VALUE Backend_accept(VALUE self, VALUE server_socket, VALUE socket_class) {
  Backend_t *backend;
  GetBackend(self, backend);
  return io_uring_backend_accept(backend, server_socket, socket_class, 0);
}

VALUE Backend_accept_loop(VALUE self, VALUE server_socket, VALUE socket_class) {
  Backend_t *backend;
  GetBackend(self, backend);
  io_uring_backend_accept(backend, server_socket, socket_class, 1);
  return self;
}

VALUE Backend_connect(VALUE self, VALUE sock, VALUE host, VALUE port) {
  Backend_t *backend;
  rb_io_t *fptr;
  struct sockaddr_in addr;
  char *host_buf = StringValueCStr(host);
  VALUE underlying_sock = rb_ivar_get(sock, ID_ivar_io);
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetBackend(self, backend);
  GetOpenFile(sock, fptr);
  io_unset_nonblock(fptr, sock);

  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = inet_addr(host_buf);
  addr.sin_port = htons(NUM2INT(port));

  VALUE resume_value = Qnil;
  op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_CONNECT);
  struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
  io_uring_prep_connect(sqe, fptr->fd, (struct sockaddr *)&addr, sizeof(addr));
  int result = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
  OP_CONTEXT_RELEASE(&backend->store, ctx);
  RAISE_IF_EXCEPTION(resume_value);
  if (!ctx->completed) return resume_value;
  RB_GC_GUARD(resume_value);
  
  if (result < 0) rb_syserr_fail(-result, strerror(-result));
  return sock;
}

VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  GetOpenFile(io, fptr);
  io_unset_nonblock(fptr, io);

  VALUE resume_value = io_uring_backend_wait_fd(backend, fptr->fd, RTEST(write));
  RAISE_IF_EXCEPTION(resume_value);
  RB_GC_GUARD(resume_value);
  return self;
}

inline struct __kernel_timespec double_to_timespec(double duration) {
  double duration_integral;
  double duration_fraction = modf(duration, &duration_integral);
  struct __kernel_timespec ts;
  ts.tv_sec = duration_integral;
	ts.tv_nsec = floor(duration_fraction * 1000000000);
  return ts;
}

inline struct __kernel_timespec duration_to_timespec(VALUE duration) {
  return double_to_timespec(NUM2DBL(duration));
}

// returns true if completed, 0 otherwise
int io_uring_backend_submit_timeout_and_await(Backend_t *backend, double duration, VALUE *resume_value) {
  struct __kernel_timespec ts = double_to_timespec(duration);
  struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
  
  op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_TIMEOUT);
  io_uring_prep_timeout(sqe, &ts, 0, 0);

  io_uring_backend_defer_submit_and_await(backend, sqe, ctx, resume_value);
  OP_CONTEXT_RELEASE(&backend->store, ctx);
  return ctx->completed;
}

VALUE Backend_sleep(VALUE self, VALUE duration) {
  Backend_t *backend;
  GetBackend(self, backend);

  VALUE resume_value = Qnil;
  io_uring_backend_submit_timeout_and_await(backend, NUM2DBL(duration), &resume_value);
  RAISE_IF_EXCEPTION(resume_value);
  RB_GC_GUARD(resume_value);
  return resume_value;
}

VALUE Backend_timer_loop(VALUE self, VALUE interval) {
  Backend_t *backend;
  double interval_d = NUM2DBL(interval);
  GetBackend(self, backend);
  double next_time = 0.;

  while (1) {
    double now = current_time();
    if (next_time == 0.) next_time = current_time() + interval_d;
    double sleep_duration = next_time - now;
    if (sleep_duration < 0) sleep_duration = 0;
    
    VALUE resume_value = Qnil;
    int completed = io_uring_backend_submit_timeout_and_await(backend, sleep_duration, &resume_value);
    RAISE_IF_EXCEPTION(resume_value);
    if (!completed) return resume_value;
    RB_GC_GUARD(resume_value);

    rb_yield(Qnil);

    while (1) {
      next_time += interval_d;
      if (next_time > now) break;
    }
  }
}

struct Backend_timeout_ctx {
  Backend_t *backend;
  op_context_t *ctx;
};

VALUE Backend_timeout_ensure(VALUE arg) {
    struct Backend_timeout_ctx *timeout_ctx = (struct Backend_timeout_ctx *)arg;
    if (!timeout_ctx->ctx->completed) {
    timeout_ctx->ctx->result = -ECANCELED;

    // op was not completed, so we need to cancel it
    struct io_uring_sqe *sqe = io_uring_get_sqe(&timeout_ctx->backend->ring);
    io_uring_prep_cancel(sqe, timeout_ctx->ctx, 0);
    timeout_ctx->backend->pending_sqes = 0;
    io_uring_submit(&timeout_ctx->backend->ring);
  }
  OP_CONTEXT_RELEASE(&timeout_ctx->backend->store, timeout_ctx->ctx);
  return Qnil;
}

VALUE Backend_timeout(int argc, VALUE *argv, VALUE self) {
  VALUE duration;
  VALUE exception;
  VALUE move_on_value = Qnil;
  rb_scan_args(argc, argv, "21", &duration, &exception, &move_on_value);
  
  struct __kernel_timespec ts = duration_to_timespec(duration);
  Backend_t *backend;
  GetBackend(self, backend);
  VALUE result = Qnil;
  VALUE timeout = rb_funcall(cTimeoutException, ID_new, 0);

  struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
  
  op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_TIMEOUT);
  ctx->resume_value = timeout;
  io_uring_prep_timeout(sqe, &ts, 0, 0);
  io_uring_sqe_set_data(sqe, ctx);
  io_uring_backend_defer_submit(backend);

  struct Backend_timeout_ctx timeout_ctx = {backend, ctx};
  result = rb_ensure(Backend_timeout_ensure_safe, Qnil, Backend_timeout_ensure, (VALUE)&timeout_ctx);

  if (result == timeout) {
    if (exception == Qnil) return move_on_value;
    RAISE_EXCEPTION(backend_timeout_exception(exception));
  }

  RAISE_IF_EXCEPTION(result);
  RB_GC_GUARD(result);
  RB_GC_GUARD(timeout);
  return result;
}

VALUE Backend_waitpid(VALUE self, VALUE pid) {
  int pid_int = NUM2INT(pid);
  int fd = pidfd_open(pid_int, 0);

  if (fd >= 0) {
    Backend_t *backend;
    GetBackend(self, backend);

    VALUE resume_value = io_uring_backend_wait_fd(backend, fd, 0);
    close(fd);
    RAISE_IF_EXCEPTION(resume_value);
    RB_GC_GUARD(resume_value);
  }
  
  int status;
  pid_t ret = waitpid(pid_int, &status, WNOHANG);
  if (ret < 0) {
    int e = errno;
    if (e == ECHILD)
      ret = pid_int;
    else
      rb_syserr_fail(e, strerror(e));
  }
  return rb_ary_new_from_args(2, INT2NUM(ret), INT2NUM(WEXITSTATUS(status)));
}

VALUE Backend_wait_event(VALUE self, VALUE raise) {
  Backend_t *backend;
  GetBackend(self, backend);

  if (backend->event_fd == -1) {
    backend->event_fd = eventfd(0, 0);
    if (backend->event_fd == -1) {
      int n = errno;
      rb_syserr_fail(n, strerror(n));
    }
  }

  VALUE resume_value = io_uring_backend_wait_fd(backend, backend->event_fd, 0);
  if (RTEST(raise)) RAISE_IF_EXCEPTION(resume_value);
  RB_GC_GUARD(resume_value);
  return resume_value;
}

VALUE Backend_kind(VALUE self) {
  return SYM_io_uring;
}

void Init_Backend() {
  VALUE cBackend = rb_define_class_under(mPolyphony, "Backend", rb_cObject);
  rb_define_alloc_func(cBackend, Backend_allocate);

  rb_define_method(cBackend, "initialize", Backend_initialize, 0);
  rb_define_method(cBackend, "finalize", Backend_finalize, 0);
  rb_define_method(cBackend, "post_fork", Backend_post_fork, 0);

  rb_define_method(cBackend, "poll", Backend_poll, 3);
  rb_define_method(cBackend, "break", Backend_wakeup, 0);

  rb_define_method(cBackend, "read", Backend_read, 4);
  rb_define_method(cBackend, "read_loop", Backend_read_loop, 1);
  rb_define_method(cBackend, "feed_loop", Backend_feed_loop, 3);
  rb_define_method(cBackend, "write", Backend_write_m, -1);
  rb_define_method(cBackend, "recv", Backend_recv, 3);
  rb_define_method(cBackend, "recv_loop", Backend_recv_loop, 1);
  rb_define_method(cBackend, "recv_feed_loop", Backend_recv_feed_loop, 3);
  rb_define_method(cBackend, "send", Backend_send, 2);
  rb_define_method(cBackend, "accept", Backend_accept, 2);
  rb_define_method(cBackend, "accept_loop", Backend_accept_loop, 2);
  rb_define_method(cBackend, "connect", Backend_connect, 3);
  rb_define_method(cBackend, "wait_io", Backend_wait_io, 2);
  rb_define_method(cBackend, "sleep", Backend_sleep, 1);
  rb_define_method(cBackend, "timer_loop", Backend_timer_loop, 1);
  rb_define_method(cBackend, "timeout", Backend_timeout, -1);
  rb_define_method(cBackend, "waitpid", Backend_waitpid, 1);
  rb_define_method(cBackend, "wait_event", Backend_wait_event, 1);

  rb_define_method(cBackend, "kind", Backend_kind, 0);

  #ifdef POLYPHONY_UNSET_NONBLOCK
  ID_ivar_is_nonblocking = rb_intern("@is_nonblocking");
  #endif

  SYM_io_uring = ID2SYM(rb_intern("io_uring"));
}

#endif // POLYPHONY_BACKEND_LIBURING
