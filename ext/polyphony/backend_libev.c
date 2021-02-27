/*
# Libev-based blocking ops backend for Polyphony

## Backend initialization

The backend is initialized by creating an event loop. For the main thread the
default event loop is used, but we since we don't need to handle any signals
(see the waitpid implementation below) we might as well use a non-default event
loop for the main thread at some time in the future.

In addition, we create an async watcher that is used for interrupting the #poll
method from another thread.

## Blocking operations

I/O operations start by making sure the io has been set to non-blocking
operation (O_NONBLOCK). That way, if the syscall would block, we'd get an
EWOULDBLOCK or EAGAIN instead of blocking.

Once the OS has indicated that the operation would block, we start a watcher
(its type corresponding to the desired operation), and call ev_xxxx_start. in We
then call Thread_switch_fiber and switch to another fiber while waiting for the
watcher to be triggered.

## Polling for events

Backend_poll is called either once the corresponding thread has no more work to
do (no runnable fibers) or periodically while the thread is scheduling fibers in
order to prevent event starvation.

## Behaviour of waitpid

On Linux 5.3+, pidfd_open will be used, otherwise a libev child watcher will be
used. Note that if a child watcher is used, waitpid will only work from the main
thread.

*/

#ifdef POLYPHONY_BACKEND_LIBEV

#include <netdb.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdnoreturn.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "polyphony.h"
#include "../libev/ev.h"
#include "ruby/io.h"

VALUE SYM_libev;

ID ID_ivar_is_nonblocking;

// Since we need to ensure that fd's are non-blocking before every I/O
// operation, here we improve upon Ruby's rb_io_set_nonblock by caching the
// "nonblock" state in an instance variable. Calling rb_ivar_get on every read
// is still much cheaper than doing a fcntl syscall on every read! Preliminary
// benchmarks (with a "hello world" HTTP server) show throughput is improved
// by 10-13%.
inline void io_set_nonblock(rb_io_t *fptr, VALUE io) {
  VALUE is_nonblocking = rb_ivar_get(io, ID_ivar_is_nonblocking);
  if (is_nonblocking == Qtrue) return;

  rb_ivar_set(io, ID_ivar_is_nonblocking, Qtrue);

#ifdef _WIN32
  rb_w32_set_nonblock(fptr->fd);
#elif defined(F_GETFL)
  int oflags = fcntl(fptr->fd, F_GETFL);
  if ((oflags == -1) && (oflags & O_NONBLOCK)) return;
  oflags |= O_NONBLOCK;
  fcntl(fptr->fd, F_SETFL, oflags);
#endif
}

typedef struct Backend_t {
  // common fields
  unsigned int        currently_polling;
  unsigned int        pending_count;
  unsigned int        poll_no_wait_count;

  // implementation-specific fields
  struct ev_loop *ev_loop;
  struct ev_async break_async;
} Backend_t;

static size_t Backend_size(const void *ptr) {
  return sizeof(Backend_t);
}

static const rb_data_type_t Backend_type = {
    "LibevBackend",
    {0, 0, Backend_size,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE Backend_allocate(VALUE klass) {
  Backend_t *backend = ALLOC(Backend_t);

  return TypedData_Wrap_Struct(klass, &Backend_type, backend);
}

#define GetBackend(obj, backend) \
  TypedData_Get_Struct((obj), Backend_t, &Backend_type, (backend))

void break_async_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  // This callback does nothing, the break async is used solely for breaking out
  // of a *blocking* event loop (waking it up) in a thread-safe, signal-safe manner
}

static VALUE Backend_initialize(VALUE self) {
  Backend_t *backend;
  VALUE thread = rb_thread_current();
  int is_main_thread = (thread == rb_thread_main());

  GetBackend(self, backend);
  backend->ev_loop = is_main_thread ? EV_DEFAULT : ev_loop_new(EVFLAG_NOSIGMASK);

  ev_async_init(&backend->break_async, break_async_callback);
  ev_async_start(backend->ev_loop, &backend->break_async);
  ev_unref(backend->ev_loop); // don't count the break_async watcher

  backend->currently_polling = 0;
  backend->pending_count = 0;
  backend->poll_no_wait_count = 0;

  return Qnil;
}

VALUE Backend_finalize(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

   ev_async_stop(backend->ev_loop, &backend->break_async);

  if (!ev_is_default_loop(backend->ev_loop)) ev_loop_destroy(backend->ev_loop);

  return self;
}

VALUE Backend_post_fork(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  // After fork there may be some watchers still active left over from the
  // parent, so we destroy the loop, even if it's the default one, then use the
  // default one, as post_fork is called only from the main thread of the forked
  // process. That way we don't need to call ev_loop_fork, since the loop is
  // always a fresh one.
  ev_loop_destroy(backend->ev_loop);
  backend->ev_loop = EV_DEFAULT;

  return self;
}

unsigned int Backend_pending_count(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  return backend->pending_count;
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

  COND_TRACE(2, SYM_fiber_event_poll_enter, current_fiber);
  backend->currently_polling = 1;
  ev_run(backend->ev_loop, is_nowait ? EVRUN_NOWAIT : EVRUN_ONCE);
  backend->currently_polling = 0;
  COND_TRACE(2, SYM_fiber_event_poll_leave, current_fiber);

  return self;
}

VALUE Backend_wakeup(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  if (backend->currently_polling) {
    // Since the loop will run until at least one event has occurred, we signal
    // the selector's associated async watcher, which will cause the ev loop to
    // return. In contrast to using `ev_break` to break out of the loop, which
    // should be called from the same thread (from within the ev_loop), using an
    // `ev_async` allows us to interrupt the event loop across threads.
    ev_async_send(backend->ev_loop, &backend->break_async);
    return Qtrue;
  }

  return Qnil;
}

#include "../libev/ev.h"

#include "backend_common.h"

struct libev_io {
  struct ev_io io;
  VALUE fiber;
};

void Backend_io_callback(EV_P_ ev_io *w, int revents)
{
  struct libev_io *watcher = (struct libev_io *)w;
  Fiber_make_runnable(watcher->fiber, Qnil);
}

VALUE libev_wait_fd_with_watcher(Backend_t *backend, int fd, struct libev_io *watcher, int events) {
  VALUE switchpoint_result;

  if (watcher->fiber == Qnil) {
    watcher->fiber = rb_fiber_current();
    ev_io_init(&watcher->io, Backend_io_callback, fd, events);
  }
  ev_io_start(backend->ev_loop, &watcher->io);

  switchpoint_result = backend_await(backend);

  ev_io_stop(backend->ev_loop, &watcher->io);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

VALUE libev_wait_fd(Backend_t *backend, int fd, int events, int raise_exception) {
  struct libev_io watcher;
  VALUE switchpoint_result = Qnil;
  watcher.fiber = Qnil;

  switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, events);

  if (raise_exception) RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

VALUE Backend_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  long dynamic_len = length == Qnil;
  long len = dynamic_len ? 4096 : NUM2INT(length);
  int shrinkable = io_setstrbuf(&str, len);
  char *buf = RSTRING_PTR(str);
  long total = 0;
  VALUE switchpoint_result = Qnil;
  int read_to_eof = RTEST(to_eof);
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_set_nonblock(fptr, io);
  rectify_io_file_pos(fptr);
  watcher.fiber = Qnil;
  OBJ_TAINT(str);

  while (1) {
    ssize_t n = read(fptr->fd, buf, len - total);
    if (n < 0) {
      int e = errno;
      if (e != EWOULDBLOCK && e != EAGAIN) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_READ);

      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = backend_snooze();

      if (TEST_EXCEPTION(switchpoint_result)) goto error;

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

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return str;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_recv(VALUE self, VALUE io, VALUE str, VALUE length) {
  return Backend_read(self, io, str, length, Qnil);
}

VALUE Backend_read_loop(VALUE self, VALUE io) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE str;
  long total;
  long len = 8192;
  int shrinkable;
  char *buf;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_set_nonblock(fptr, io);
  rectify_io_file_pos(fptr);
  watcher.fiber = Qnil;

  while (1) {
    ssize_t n = read(fptr->fd, buf, len);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_READ);
      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = backend_snooze();

      if (TEST_EXCEPTION(switchpoint_result)) goto error;

      if (n == 0) break; // EOF
      total = n;
      READ_LOOP_YIELD_STR();
    }
  }

  RB_GC_GUARD(str);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return io;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE str;
  long total;
  long len = 8192;
  int shrinkable;
  char *buf;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);
  ID method_id = SYM2ID(method);

  READ_LOOP_PREPARE_STR();

  GetBackend(self, backend);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  io_set_nonblock(fptr, io);
  rectify_io_file_pos(fptr);
  watcher.fiber = Qnil;

  while (1) {
    ssize_t n = read(fptr->fd, buf, len);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_READ);
      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = backend_snooze();

      if (TEST_EXCEPTION(switchpoint_result)) goto error;

      if (n == 0) break; // EOF
      total = n;
      READ_LOOP_PASS_STR_TO_RECEIVER(receiver, method_id);
    }
  }

  RB_GC_GUARD(str);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return io;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_write(VALUE self, VALUE io, VALUE str) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_io;
  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;

  underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);
  io_set_nonblock(fptr, io);
  watcher.fiber = Qnil;

  while (left > 0) {
    ssize_t n = write(fptr->fd, buf, left);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_WRITE);

      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      buf += n;
      left -= n;
    }
  }

  if (watcher.fiber == Qnil) {
    switchpoint_result = backend_snooze();

    if (TEST_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2NUM(len);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_writev(VALUE self, VALUE io, int argc, VALUE *argv) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;
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
  io_set_nonblock(fptr, io);
  watcher.fiber = Qnil;

  iov = malloc(iov_count * sizeof(struct iovec));
  for (int i = 0; i < argc; i++) {
    VALUE str = argv[i];
    iov[i].iov_base = StringValuePtr(str);
    iov[i].iov_len = RSTRING_LEN(str);
    total_length += iov[i].iov_len;
  }
  iov_ptr = iov;

  while (1) {
    ssize_t n = writev(fptr->fd, iov_ptr, iov_count);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) {
        free(iov);
        rb_syserr_fail(e, strerror(e));
      }

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_WRITE);

      if (TEST_EXCEPTION(switchpoint_result)) goto error;
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
  if (watcher.fiber == Qnil) {
    switchpoint_result = backend_snooze();
    if (TEST_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
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

  return (argc == 2) ?
    Backend_write(self, argv[0], argv[1]) :
    Backend_writev(self, argv[0], argc - 1, argv + 1);
}

VALUE Backend_accept(VALUE self, VALUE server_socket, VALUE socket_class) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_sock = rb_ivar_get(server_socket, ID_ivar_io);
  if (underlying_sock != Qnil) server_socket = underlying_sock;

  GetBackend(self, backend);
  GetOpenFile(server_socket, fptr);
  io_set_nonblock(fptr, server_socket);
  watcher.fiber = Qnil;
  while (1) {
    fd = accept(fptr->fd, &addr, &len);
    if (fd < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_READ);

      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      VALUE socket;
      rb_io_t *fp;
      switchpoint_result = backend_snooze();

      if (TEST_EXCEPTION(switchpoint_result)) {
        close(fd); // close fd since we're raising an exception
        goto error;
      }

      socket = rb_obj_alloc(socket_class);
      MakeOpenFile(socket, fp);
      rb_update_max_fd(fd);
      fp->fd = fd;
      fp->mode = FMODE_READWRITE | FMODE_DUPLEX;
      rb_io_ascii8bit_binmode(socket);
      io_set_nonblock(fp, socket);
      rb_io_synchronized(fp);

      // if (rsock_do_not_reverse_lookup) {
	    //   fp->mode |= FMODE_NOREVLOOKUP;
      // }
      return socket;
    }
  }
  RB_GC_GUARD(switchpoint_result);
  return Qnil;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_accept_loop(VALUE self, VALUE server_socket, VALUE socket_class) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;
  VALUE socket = Qnil;
  VALUE underlying_sock = rb_ivar_get(server_socket, ID_ivar_io);
  if (underlying_sock != Qnil) server_socket = underlying_sock;

  GetBackend(self, backend);
  GetOpenFile(server_socket, fptr);
  io_set_nonblock(fptr, server_socket);
  watcher.fiber = Qnil;

  while (1) {
    fd = accept(fptr->fd, &addr, &len);
    if (fd < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_READ);

      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      rb_io_t *fp;
      switchpoint_result = backend_snooze();

      if (TEST_EXCEPTION(switchpoint_result)) {
        close(fd); // close fd since we're raising an exception
        goto error;
      }

      socket = rb_obj_alloc(socket_class);
      MakeOpenFile(socket, fp);
      rb_update_max_fd(fd);
      fp->fd = fd;
      fp->mode = FMODE_READWRITE | FMODE_DUPLEX;
      rb_io_ascii8bit_binmode(socket);
      io_set_nonblock(fp, socket);
      rb_io_synchronized(fp);

      rb_yield(socket);
      socket = Qnil;
    }
  }

  RB_GC_GUARD(socket);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return Qnil;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_connect(VALUE self, VALUE sock, VALUE host, VALUE port) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  struct sockaddr_in addr;
  char *host_buf = StringValueCStr(host);
  VALUE switchpoint_result = Qnil;
  VALUE underlying_sock = rb_ivar_get(sock, ID_ivar_io);
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetBackend(self, backend);
  GetOpenFile(sock, fptr);
  io_set_nonblock(fptr, sock);
  watcher.fiber = Qnil;

  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = inet_addr(host_buf);
  addr.sin_port = htons(NUM2INT(port));

  int result = connect(fptr->fd, (struct sockaddr *)&addr, sizeof(addr));
  if (result < 0) {
    int e = errno;
    if (e != EINPROGRESS) rb_syserr_fail(e, strerror(e));

    switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_WRITE);

    if (TEST_EXCEPTION(switchpoint_result)) goto error;
  }
  else {
    switchpoint_result = backend_snooze();

    if (TEST_EXCEPTION(switchpoint_result)) goto error;
  }
  RB_GC_GUARD(switchpoint_result);
  return sock;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_send(VALUE self, VALUE io, VALUE str, VALUE flags) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_io;
  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;
  int flags_int = NUM2INT(flags);

  underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);
  io_set_nonblock(fptr, io);
  watcher.fiber = Qnil;

  while (left > 0) {
    ssize_t n = send(fptr->fd, buf, left, flags_int);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fptr->fd, &watcher, EV_WRITE);

      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      buf += n;
      left -= n;
    }
  }

  if (watcher.fiber == Qnil) {
    switchpoint_result = backend_snooze();

    if (TEST_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2NUM(len);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write) {
  Backend_t *backend;
  rb_io_t *fptr;
  int events = RTEST(write) ? EV_WRITE : EV_READ;
  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;
  GetBackend(self, backend);
  GetOpenFile(io, fptr);

  return libev_wait_fd(backend, fptr->fd, events, 1);
}

struct libev_timer {
  struct ev_timer timer;
  VALUE fiber;
};

void Backend_timer_callback(EV_P_ ev_timer *w, int revents)
{
  struct libev_timer *watcher = (struct libev_timer *)w;
  Fiber_make_runnable(watcher->fiber, Qnil);
}

VALUE Backend_sleep(VALUE self, VALUE duration) {
  Backend_t *backend;
  struct libev_timer watcher;
  VALUE switchpoint_result = Qnil;

  GetBackend(self, backend);
  watcher.fiber = rb_fiber_current();
  ev_timer_init(&watcher.timer, Backend_timer_callback, NUM2DBL(duration), 0.);
  ev_timer_start(backend->ev_loop, &watcher.timer);

  switchpoint_result = backend_await(backend);

  ev_timer_stop(backend->ev_loop, &watcher.timer);
  RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

noreturn VALUE Backend_timer_loop(VALUE self, VALUE interval) {
  Backend_t *backend;
  struct libev_timer watcher;
  double interval_d = NUM2DBL(interval);

  GetBackend(self, backend);
  watcher.fiber = rb_fiber_current();

  double next_time = 0.;

  while (1) {
    double now = current_time();
    if (next_time == 0.) next_time = current_time() + interval_d;
    double sleep_duration = next_time - now;
    if (sleep_duration < 0) sleep_duration = 0;
    
    VALUE switchpoint_result = Qnil;    
    ev_timer_init(&watcher.timer, Backend_timer_callback, sleep_duration, 0.);
    ev_timer_start(backend->ev_loop, &watcher.timer);
    switchpoint_result = backend_await(backend);
    ev_timer_stop(backend->ev_loop, &watcher.timer);
    RAISE_IF_EXCEPTION(switchpoint_result);
    RB_GC_GUARD(switchpoint_result);

    rb_yield(Qnil);
    do {
      next_time += interval_d;
    } while (next_time <= now);
  }
}

struct libev_timeout {
  struct ev_timer timer;
  VALUE fiber;
  VALUE resume_value;
};

struct Backend_timeout_ctx {
  Backend_t *backend;
  struct libev_timeout *watcher;
};

VALUE Backend_timeout_ensure(VALUE arg) {
  struct Backend_timeout_ctx *timeout_ctx = (struct Backend_timeout_ctx *)arg;
  ev_timer_stop(timeout_ctx->backend->ev_loop, &(timeout_ctx->watcher->timer));
  return Qnil;
}

void Backend_timeout_callback(EV_P_ ev_timer *w, int revents)
{
  struct libev_timeout *watcher = (struct libev_timeout *)w;
  Fiber_make_runnable(watcher->fiber, watcher->resume_value);
}

VALUE Backend_timeout(int argc,VALUE *argv, VALUE self) {
  VALUE duration;
  VALUE exception;
  VALUE move_on_value = Qnil;
  rb_scan_args(argc, argv, "21", &duration, &exception, &move_on_value);

  Backend_t *backend;
  struct libev_timeout watcher;
  VALUE result = Qnil;
  VALUE timeout = rb_funcall(cTimeoutException, ID_new, 0);

  GetBackend(self, backend);
  watcher.fiber = rb_fiber_current();
  watcher.resume_value = timeout;
  ev_timer_init(&watcher.timer, Backend_timeout_callback, NUM2DBL(duration), 0.);
  ev_timer_start(backend->ev_loop, &watcher.timer);

  struct Backend_timeout_ctx timeout_ctx = {backend, &watcher};
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

#ifdef POLYPHONY_USE_PIDFD_OPEN
VALUE Backend_waitpid(VALUE self, VALUE pid) {
  int pid_int = NUM2INT(pid);
  int fd = pidfd_open(pid_int, 0);
  if (fd >= 0) {
    Backend_t *backend;
    GetBackend(self, backend);

    VALUE resume_value = libev_wait_fd(backend, fd, EV_READ, 0);
    close(fd);
    RAISE_IF_EXCEPTION(resume_value);
    RB_GC_GUARD(resume_value);
  }
  else {
    int e = errno;
    printf("  errno: %d\n", e);
  }

  int status = 0;
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
#else
struct libev_child {
  struct ev_child child;
  VALUE fiber;
};

void Backend_child_callback(EV_P_ ev_child *w, int revents) {
  struct libev_child *watcher = (struct libev_child *)w;
  int exit_status = WEXITSTATUS(w->rstatus);
  VALUE status;

  status = rb_ary_new_from_args(2, INT2NUM(w->rpid), INT2NUM(exit_status));
  Fiber_make_runnable(watcher->fiber, status);
}

VALUE Backend_waitpid(VALUE self, VALUE pid) {
  Backend_t *backend;
  struct libev_child watcher;
  VALUE switchpoint_result = Qnil;
  GetBackend(self, backend);

  watcher.fiber = rb_fiber_current();
  ev_child_init(&watcher.child, Backend_child_callback, NUM2INT(pid), 0);
  ev_child_start(backend->ev_loop, &watcher.child);

  switchpoint_result = backend_await(backend);

  ev_child_stop(backend->ev_loop, &watcher.child);
  RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}
#endif

void Backend_async_callback(EV_P_ ev_async *w, int revents) { }

VALUE Backend_wait_event(VALUE self, VALUE raise) {
  Backend_t *backend;
  VALUE switchpoint_result = Qnil;
  GetBackend(self, backend);

  struct ev_async async;

  ev_async_init(&async, Backend_async_callback);
  ev_async_start(backend->ev_loop, &async);

  switchpoint_result = backend_await(backend);

  ev_async_stop(backend->ev_loop, &async);
  if (RTEST(raise)) RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

VALUE Backend_kind(VALUE self) {
  return SYM_libev;
}

void Init_Backend() {
  ev_set_allocator(xrealloc);

  VALUE cBackend = rb_define_class_under(mPolyphony, "Backend", rb_cData);
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
  rb_define_method(cBackend, "accept", Backend_accept, 2);
  rb_define_method(cBackend, "accept_loop", Backend_accept_loop, 2);
  rb_define_method(cBackend, "connect", Backend_connect, 3);
  rb_define_method(cBackend, "recv", Backend_recv, 3);
  rb_define_method(cBackend, "recv_loop", Backend_read_loop, 1);
  rb_define_method(cBackend, "recv_feed_loop", Backend_feed_loop, 3);
  rb_define_method(cBackend, "send", Backend_send, 3);
  rb_define_method(cBackend, "sendv", Backend_sendv, 3);
  rb_define_method(cBackend, "wait_io", Backend_wait_io, 2);
  rb_define_method(cBackend, "sleep", Backend_sleep, 1);
  rb_define_method(cBackend, "timer_loop", Backend_timer_loop, 1);
  rb_define_method(cBackend, "timeout", Backend_timeout, -1);
  rb_define_method(cBackend, "waitpid", Backend_waitpid, 1);
  rb_define_method(cBackend, "wait_event", Backend_wait_event, 1);

  rb_define_method(cBackend, "kind", Backend_kind, 0);

  ID_ivar_is_nonblocking = rb_intern("@is_nonblocking");
  SYM_libev = ID2SYM(rb_intern("libev"));
}

#endif // POLYPHONY_BACKEND_LIBEV
