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
#include "backend_io_uring_context.h"

#include <poll.h>
#include <sys/types.h>
#include <sys/eventfd.h>
#include <sys/wait.h>
#include <errno.h>

#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434   /* System call # on most architectures */
#endif

static int pidfd_open(pid_t pid, unsigned int flags) {
  return syscall(__NR_pidfd_open, pid, flags);
}

VALUE cTCPSocket;

typedef struct Backend_t {
  struct io_uring     ring;
  op_context_store_t  store;
  int                 waiting_for_cqe;
  unsigned int        ref_count;
  unsigned int        run_no_wait_count;
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

  backend->waiting_for_cqe = 0;
  backend->ref_count = 0;
  backend->run_no_wait_count = 0;
  backend->pending_sqes = 0;
  backend->prepared_limit = 1024;

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
  backend->pending_sqes = 0;

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

typedef struct poll_context {
  struct io_uring     *ring;
  struct io_uring_cqe *cqe;
  int                 pending_sqes;
  int                 result;
} poll_context_t;

void *io_uring_backend_poll_without_gvl(void *ptr) {
  poll_context_t *ctx = (poll_context_t *)ptr;
  ctx->result = __io_uring_get_cqe(ctx->ring, &ctx->cqe, ctx->pending_sqes, 1, 0);
  return 0;
}

// copied from queue.c
static inline bool cq_ring_needs_flush(struct io_uring *ring) {
	return IO_URING_READ_ONCE(*ring->sq.kflags) & IORING_SQ_CQ_OVERFLOW;
}

extern int __sys_io_uring_enter(int fd, unsigned to_submit, unsigned min_complete, unsigned flags, sigset_t *sig);

void io_uring_backend_handle_completion(struct io_uring_cqe *cqe, Backend_t *backend) {
  op_context_t *ctx = io_uring_cqe_get_data(cqe);
  if (ctx == 0) return;

  ctx->result = cqe->res;
  if (ctx->completed)
    // already marked as deleted as result of fiber resuming before op
    // completion, so we can release the context
    context_store_release(&backend->store, ctx);
  else {
    // otherwise, we mark it as completed, schedule the fiber and let it deal
    // with releasing the context
    ctx->completed = 1;
    if (ctx->result != -ECANCELED) Fiber_make_runnable(ctx->fiber, Qnil);
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
  poll_ctx.pending_sqes = 0; // TODO: perform submission in same syscall
  backend->waiting_for_cqe = 1;
  rb_thread_call_without_gvl(io_uring_backend_poll_without_gvl, (void *)&poll_ctx, RUBY_UBF_IO, 0);
  backend->waiting_for_cqe = 0;
  if (poll_ctx.result < 0) return;

  io_uring_backend_handle_completion(poll_ctx.cqe, backend);
  io_uring_cqe_seen(&backend->ring, poll_ctx.cqe);
}

extern int __io_uring_flush_sq(struct io_uring *ring);

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

  if (backend->pending_sqes) {
    backend->pending_sqes = 0;
    io_uring_submit(&backend->ring);
  }

  COND_TRACE(2, SYM_backend_poll_enter, current_fiber);
  if (!is_nowait) io_uring_backend_poll(backend);
  io_uring_backend_handle_ready_cqes(backend);
  COND_TRACE(2, SYM_backend_poll_leave, current_fiber);
  
  return self;
}

VALUE Backend_wakeup(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  if (backend->waiting_for_cqe) {
    // Since we're currently blocking while waiting for a completion, we add a
    // NOP which would case the io_uring_enter syscall to return
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

  backend->ref_count++;
  switchpoint_result = backend_await(backend);
  backend->ref_count--;

  if (!ctx->completed) {
    // op was not completed, so we need to cancel it
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_cancel(sqe, ctx, 0);
    backend->pending_sqes = 0;
    io_uring_submit(&backend->ring);
  }

  if (value_ptr) (*value_ptr) = switchpoint_result;
  RB_GC_GUARD(switchpoint_result);
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
  VALUE underlying_io = rb_iv_get(io, "@io");
  struct iovec iov[1];

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  rectify_io_file_pos(fptr);
  OBJ_TAINT(str);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_READV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    iov[0].iov_base = buf;
    iov[0].iov_len = len - total;
    io_uring_prep_readv(sqe, fptr->fd, iov, 1, -1);
    io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    if (TEST_EXCEPTION(resume_value)) {
      OP_CONTEXT_RELEASE(&backend->store, ctx);
      RAISE_EXCEPTION(resume_value);
    }
    RB_GC_GUARD(resume_value);

    ssize_t n = ctx->result;
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    if (n < 0)
      rb_syserr_fail(-n, strerror(-n));
    else {
      if (n == 0) break; // EOF
      total = total + n;
      if (!read_to_eof) break;

      if (total == len) {
        if (!dynamic_len) break;

        rb_str_resize(str, total);
        rb_str_modify_expand(str, len);
        buf = RSTRING_PTR(str) + total;
        shrinkable = 0;
        len += len;
      }
      else buf += n;
    }
  }

  io_set_read_length(str, total, shrinkable);
  io_enc_str(str, fptr);

  if (total == 0) return Qnil;

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
  struct iovec iov[1];
  VALUE underlying_io = rb_iv_get(io, "@io");

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  rectify_io_file_pos(fptr);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_READV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    iov[0].iov_base = buf;
    iov[0].iov_len = len;
    io_uring_prep_readv(sqe, fptr->fd, iov, 1, -1);
    io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    if (TEST_EXCEPTION(resume_value)) {
      OP_CONTEXT_RELEASE(&backend->store, ctx);
      RAISE_EXCEPTION(resume_value);
    }
    RB_GC_GUARD(resume_value);

    ssize_t n = ctx->result;
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    ctx = NULL;
    if (n < 0) {
      rb_syserr_fail(-n, strerror(-n));
    }
    else if (n == 0)
      break; // EOF
    else {
      total = n;
      READ_LOOP_YIELD_STR();
    }
  }

  RB_GC_GUARD(str);

  return io;
}

VALUE Backend_write(VALUE self, VALUE io, VALUE str) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io;

  underlying_io = rb_iv_get(io, "@io");
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);

  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;

  while (left > 0) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_WRITE);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_write(sqe, fptr->fd, buf, left, -1);
    io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);

    if (TEST_EXCEPTION(resume_value)) {
      OP_CONTEXT_RELEASE(&backend->store, ctx);
      RAISE_EXCEPTION(resume_value);
    }
    RB_GC_GUARD(resume_value);
    
    ssize_t n = ctx->result;

    OP_CONTEXT_RELEASE(&backend->store, ctx);

    if (n < 0) {
      rb_syserr_fail(-n, strerror(-n));
    }
    else {
      buf += n;
      left -= n;
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
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_WRITEV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_writev(sqe, fptr->fd, iov_ptr, iov_count, -1);
    io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    
    if (TEST_EXCEPTION(resume_value)) {
      OP_CONTEXT_RELEASE(&backend->store, ctx);
      free(iov);
      RAISE_EXCEPTION(resume_value);
    }
    RB_GC_GUARD(resume_value);
    
    ssize_t n = ctx->result;
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    if (n < 0) {
      free(iov);
      rb_syserr_fail(-n, strerror(-n));
    }
    else {
      total_written += n;
      if (total_written >= total_length) break;

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
  VALUE underlying_io = rb_iv_get(io, "@io");

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  rectify_io_file_pos(fptr);
  OBJ_TAINT(str);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_RECV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_recv(sqe, fptr->fd, buf, len - total, 0);
    io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    if (TEST_EXCEPTION(resume_value)) {
      OP_CONTEXT_RELEASE(&backend->store, ctx);
      RAISE_EXCEPTION(resume_value);
    }
    RB_GC_GUARD(resume_value);

    ssize_t n = ctx->result;
    OP_CONTEXT_RELEASE(&backend->store, ctx);

    if (n < 0)
      rb_syserr_fail(-n, strerror(-n));
    else {
      total = total + n;
      break;
    }
  }

  io_set_read_length(str, total, shrinkable);
  io_enc_str(str, fptr);

  if (total == 0) return Qnil;

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
  VALUE underlying_io = rb_iv_get(io, "@io");

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  rectify_io_file_pos(fptr);

  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_RECV);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_recv(sqe, fptr->fd, buf, len, 0);
    io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    if (TEST_EXCEPTION(resume_value)) {
      OP_CONTEXT_RELEASE(&backend->store, ctx);
      RAISE_EXCEPTION(resume_value);
    }
    RB_GC_GUARD(resume_value);

    ssize_t n = ctx->result;
    OP_CONTEXT_RELEASE(&backend->store, ctx);

    if (n < 0)
      rb_syserr_fail(-n, strerror(-n));
    else if (n == 0)
      break; // EOF
    else {
      total = n;
      READ_LOOP_YIELD_STR();
    }
  }

  RB_GC_GUARD(str);
  return io;
}

VALUE Backend_send(VALUE self, VALUE io, VALUE str) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io;

  underlying_io = rb_iv_get(io, "@io");
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);

  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;

  while (left > 0) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_SEND);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_send(sqe, fptr->fd, buf, left, 0);
    io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    if (TEST_EXCEPTION(resume_value)) {
      OP_CONTEXT_RELEASE(&backend->store, ctx);
      RAISE_EXCEPTION(resume_value);
    }
    RB_GC_GUARD(resume_value);

    ssize_t n = ctx->result;
    OP_CONTEXT_RELEASE(&backend->store, ctx);

    if (n < 0)
      rb_syserr_fail(-n, strerror(-n));
    else {
      buf += n;
      left -= n;
    }
  }

  return INT2NUM(len);
}

VALUE io_uring_backend_accept(Backend_t *backend, VALUE sock, int loop) {
  rb_io_t *fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE underlying_sock = rb_iv_get(sock, "@io");
  VALUE socket = Qnil;
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetOpenFile(sock, fptr);
  while (1) {
    VALUE resume_value = Qnil;
    op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_ACCEPT);
    struct io_uring_sqe *sqe = io_uring_get_sqe(&backend->ring);
    io_uring_prep_accept(sqe, fptr->fd, &addr, &len, 0);
    fd = io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
    OP_CONTEXT_RELEASE(&backend->store, ctx);
    RAISE_IF_EXCEPTION(resume_value);
    RB_GC_GUARD(resume_value);

    if (fd < 0)
      rb_syserr_fail(-fd, strerror(-fd));
    else {
      rb_io_t *fp;

      socket = rb_obj_alloc(cTCPSocket);
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

VALUE Backend_accept(VALUE self, VALUE sock) {
  Backend_t *backend;
  GetBackend(self, backend);
  return io_uring_backend_accept(backend, sock, 0);
}

VALUE Backend_accept_loop(VALUE self, VALUE sock) {
  Backend_t *backend;
  GetBackend(self, backend);
  io_uring_backend_accept(backend, sock, 1);
  return self;
}

VALUE Backend_connect(VALUE self, VALUE sock, VALUE host, VALUE port) {
  Backend_t *backend;
  rb_io_t *fptr;
  struct sockaddr_in addr;
  char *host_buf = StringValueCStr(host);
  VALUE underlying_sock = rb_iv_get(sock, "@io");
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetBackend(self, backend);
  GetOpenFile(sock, fptr);

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
  RB_GC_GUARD(resume_value);
  if (result < 0) rb_syserr_fail(-result, strerror(-result));
  return sock;
}

VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write) {
  Backend_t *backend;
  rb_io_t *fptr;
  VALUE underlying_io = rb_iv_get(io, "@io");
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  GetOpenFile(io, fptr);

  VALUE resume_value = io_uring_backend_wait_fd(backend, fptr->fd, RTEST(write));
  RAISE_IF_EXCEPTION(resume_value);
  RB_GC_GUARD(resume_value);
  return self;
}

VALUE Backend_sleep(VALUE self, VALUE duration) {
  Backend_t *backend;
  struct io_uring_sqe *sqe;
  double duration_integral;
  double duration_fraction = modf(NUM2DBL(duration), &duration_integral);
  struct __kernel_timespec ts;

  GetBackend(self, backend);
  sqe = io_uring_get_sqe(&backend->ring);
  ts.tv_sec = duration_integral;
	ts.tv_nsec = floor(duration_fraction * 1000000000);
  
  VALUE resume_value = Qnil;
  op_context_t *ctx = OP_CONTEXT_ACQUIRE(&backend->store, OP_TIMEOUT);
  io_uring_prep_timeout(sqe, &ts, 0, 0);
  io_uring_backend_defer_submit_and_await(backend, sqe, ctx, &resume_value);
  OP_CONTEXT_RELEASE(&backend->store, ctx);
  RAISE_IF_EXCEPTION(resume_value);
  RB_GC_GUARD(resume_value);
  return resume_value;
}

VALUE Backend_waitpid(VALUE self, VALUE pid) {
  Backend_t *backend;
  int pid_int = NUM2INT(pid);
  int fd = pidfd_open(pid_int, 0);
  GetBackend(self, backend);
  
  VALUE resume_value = io_uring_backend_wait_fd(backend, fd, 0);
  close(fd);

  RAISE_IF_EXCEPTION(resume_value);
  RB_GC_GUARD(resume_value);

  int status;
  pid_t ret = waitpid(pid_int, &status, WNOHANG);
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
  rb_define_method(cBackend, "recv", Backend_recv, 3);
  rb_define_method(cBackend, "recv_loop", Backend_recv_loop, 1);
  rb_define_method(cBackend, "send", Backend_send, 2);
  rb_define_method(cBackend, "accept", Backend_accept, 1);
  rb_define_method(cBackend, "accept_loop", Backend_accept_loop, 1);
  rb_define_method(cBackend, "connect", Backend_connect, 3);
  rb_define_method(cBackend, "wait_io", Backend_wait_io, 2);
  rb_define_method(cBackend, "sleep", Backend_sleep, 1);
  rb_define_method(cBackend, "waitpid", Backend_waitpid, 1);
  rb_define_method(cBackend, "wait_event", Backend_wait_event, 1);

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
