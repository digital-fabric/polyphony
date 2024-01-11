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

#ifdef POLYPHONY_LINUX
#define _GNU_SOURCE 1
#endif

#include <unistd.h>
#include <stdnoreturn.h>
#include <sys/types.h>

#ifdef POLYPHONY_USE_PIDFD_OPEN
#include <sys/wait.h>
#endif

#include <fcntl.h>

#include "polyphony.h"
#include "../libev/ev.h"
#include "ruby/io.h"

#ifndef POLYPHONY_WINDOWS
#include <sys/uio.h>
#endif

#include "../libev/ev.h"
#include "backend_common.h"

VALUE SYM_libev;
VALUE SYM_send;
VALUE SYM_splice;
VALUE SYM_write;

typedef struct Backend_t {
  struct Backend_base base;

  // implementation-specific fields
  struct ev_loop *ev_loop;
  struct ev_async break_async;
} Backend_t;

static void Backend_mark(void *ptr) {
  Backend_t *backend = ptr;
  backend_base_mark(&backend->base);
}

static void Backend_free(void *ptr) {
  Backend_t *backend = ptr;
  backend_base_finalize(&backend->base);
}

static size_t Backend_size(const void *ptr) {
  return sizeof(Backend_t);
}

static const rb_data_type_t Backend_type = {
    "LibevBackend",
    {Backend_mark, Backend_free, Backend_size,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE Backend_allocate(VALUE klass) {
  Backend_t *backend = ALLOC(Backend_t);

  return TypedData_Wrap_Struct(klass, &Backend_type, backend);
}

void break_async_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  // This callback does nothing, the break async is used solely for breaking out
  // of a *blocking* event loop (waking it up) in a thread-safe, signal-safe manner
}

inline struct ev_loop *libev_new_loop(void) {
  #ifdef POLYPHONY_USE_PIDFD_OPEN
    return ev_loop_new(EVFLAG_NOSIGMASK);
  #else
    int is_main_thread = (rb_thread_current() == rb_thread_main());
    return is_main_thread ? EV_DEFAULT : ev_loop_new(EVFLAG_NOSIGMASK);
  #endif
}

static VALUE Backend_initialize(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend_base_initialize(&backend->base);
  backend->ev_loop = libev_new_loop();

  // start async watcher used for breaking a poll op (from another thread)
  ev_async_init(&backend->break_async, break_async_callback);
  ev_async_start(backend->ev_loop, &backend->break_async);
  // the break_async watcher is unreferenced, in order for Backend_poll to not
  // block when no other watcher is active
  ev_unref(backend->ev_loop);

  return Qnil;
}

VALUE Backend_finalize(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

   ev_async_stop(backend->ev_loop, &backend->break_async);

  if (!ev_is_default_loop(backend->ev_loop)) ev_loop_destroy(backend->ev_loop);

  return self;
}

VALUE Backend_post_fork(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  // After fork there may be some watchers still active left over from the
  // parent, so we destroy the loop, even if it's the default one, then use the
  // default one, as post_fork is called only from the main thread of the forked
  // process. That way we don't need to call ev_loop_fork, since the loop is
  // always a fresh one.
  ev_loop_destroy(backend->ev_loop);
  backend->ev_loop = EV_DEFAULT;

  backend_base_reset(&backend->base);

  return self;
}

inline VALUE Backend_poll(VALUE self, VALUE blocking) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend->base.poll_count++;

  COND_TRACE(&backend->base, 2, SYM_enter_poll, rb_fiber_current());

ev_run:
  backend->base.currently_polling = 1;
  errno = 0;
  ev_run(backend->ev_loop, blocking == Qtrue ? EVRUN_ONCE : EVRUN_NOWAIT);
  backend->base.currently_polling = 0;
  if (unlikely(errno == EINTR && runqueue_empty_p(&backend->base.runqueue))) goto ev_run;

  COND_TRACE(&backend->base, 2, SYM_leave_poll, rb_fiber_current());

  return self;
}

inline void Backend_schedule_fiber(VALUE thread, VALUE self, VALUE fiber, VALUE value, int prioritize) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend_base_schedule_fiber(thread, self, &backend->base, fiber, value, prioritize);
}

inline void Backend_unschedule_fiber(VALUE self, VALUE fiber) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  runqueue_delete(&backend->base.runqueue, fiber);
}

inline VALUE Backend_switch_fiber(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  return backend_base_switch_fiber(self, &backend->base);
}

VALUE Backend_wakeup(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  if (backend->base.currently_polling) {
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

inline struct backend_stats backend_get_stats(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  return backend_base_stats(&backend->base);
}

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

  switchpoint_result = backend_await((struct Backend_base *)backend);

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

static inline int fd_from_io(VALUE io, rb_io_t **fptr, int write_mode, int rectify_file_pos) {
  if (TYPE(io) == T_FIXNUM) {
    *fptr = NULL;
    return FIX2INT(io);
  }

  if (rb_obj_class(io) == cPipe) {
    *fptr = NULL;
    Pipe_verify_blocking_mode(io, Qfalse);
    return Pipe_get_fd(io, write_mode);
  }

  VALUE underlying_io = rb_ivar_get(io, ID_ivar_io);
  if (underlying_io != Qnil) io = underlying_io;

  GetOpenFile(io, *fptr);
  int fd = rb_io_descriptor(io);
  io_verify_blocking_mode(io, fd, Qfalse);
  if (rectify_file_pos) rectify_io_file_pos(*fptr);
  return fd;
}

VALUE Backend_read(VALUE self, VALUE io, VALUE buffer, VALUE length, VALUE to_eof, VALUE pos) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;

  struct backend_buffer_spec buffer_spec = backend_get_buffer_spec(buffer, 0);
  long total = 0;
  VALUE switchpoint_result = Qnil;
  int read_to_eof = RTEST(to_eof);

  backend_prepare_read_buffer(buffer, length, &buffer_spec, FIX2INT(pos));
  fd = fd_from_io(io, &fptr, 0, 1);
  watcher.fiber = Qnil;

  while (1) {
    backend->base.op_count++;
    ssize_t result = read(fd, buffer_spec.ptr, buffer_spec.len);
    if (result < 0) {
      int e = errno;
      if (e != EWOULDBLOCK && e != EAGAIN) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_READ);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = backend_snooze(&backend->base);
      if (IS_EXCEPTION(switchpoint_result)) goto error;

      if (!result) break; // EOF

      total += result;
      if (!read_to_eof) break;

      if (result == buffer_spec.len) {
        if (buffer_spec.expandable)
          backend_grow_string_buffer(buffer, &buffer_spec, total);
        else
          break;
      }
      else {
        buffer_spec.ptr += result;
        buffer_spec.len -= result;
        if (!buffer_spec.len) break;
      }
    }
  }

  if (!total) return Qnil;

  if (!buffer_spec.raw) backend_finalize_string_buffer(buffer, &buffer_spec, total, fptr);

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return buffer_spec.raw ? INT2FIX(total) : buffer;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_recv(VALUE self, VALUE io, VALUE buffer, VALUE length, VALUE pos) {
  return Backend_read(self, io, buffer, length, Qnil, pos);
}

VALUE Backend_recvmsg(VALUE self, VALUE io, VALUE buffer, VALUE maxlen, VALUE pos, VALUE flags, VALUE maxcontrollen, VALUE opts) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;

  struct backend_buffer_spec buffer_spec = backend_get_buffer_spec(buffer, 0);
  long total = 0;
  VALUE switchpoint_result = Qnil;

  backend_prepare_read_buffer(buffer, maxlen, &buffer_spec, FIX2INT(pos));
  fd = fd_from_io(io, &fptr, 0, 1);
  watcher.fiber = Qnil;

  char addr_buffer[64];
  struct iovec iov;
  struct msghdr msg;

  iov.iov_base = StringValuePtr(buffer);
  iov.iov_len = maxlen;

  msg.msg_name = addr_buffer;
  msg.msg_namelen = sizeof(addr_buffer);
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = 0;
  msg.msg_controllen = 0;
  msg.msg_flags = 0;

  while (1) {
    backend->base.op_count++;
    ssize_t result = recvmsg(fd, &msg, NUM2INT(flags));
    if (result < 0) {
      int e = errno;
      if (e != EWOULDBLOCK && e != EAGAIN) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_READ);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = backend_snooze(&backend->base);
      if (IS_EXCEPTION(switchpoint_result)) goto error;

      if (!result) break; // EOF

      total += result;
      break;
    }
  }

  if (!total) return Qnil;

  if (!buffer_spec.raw) backend_finalize_string_buffer(buffer, &buffer_spec, total, fptr);
  VALUE addr = name_to_addrinfo(msg.msg_name, msg.msg_namelen);
  VALUE rflags = INT2NUM(msg.msg_flags);

  return rb_ary_new_from_args(3, buffer, addr, rflags);
  RB_GC_GUARD(addr);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_read_loop(VALUE self, VALUE io, VALUE maxlen) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;
  VALUE buffer;
  long total;
  char *ptr;
  long len = FIX2INT(maxlen);
  int shrinkable;
  VALUE switchpoint_result = Qnil;

  READ_LOOP_PREPARE_STR();

  fd = fd_from_io(io, &fptr, 0, 1);
  watcher.fiber = Qnil;

  while (1) {
    backend->base.op_count++;
    ssize_t n = read(fd, ptr, len);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_READ);
      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = backend_snooze(&backend->base);

      if (IS_EXCEPTION(switchpoint_result)) goto error;

      if (n == 0) break; // EOF
      total = n;
      READ_LOOP_YIELD_STR();
    }
  }

  RB_GC_GUARD(buffer);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return io;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;
  VALUE buffer;
  long total;
  char *ptr;
  long len = 8192;
  int shrinkable;
  VALUE switchpoint_result = Qnil;
  ID method_id = SYM2ID(method);

  READ_LOOP_PREPARE_STR();

  fd = fd_from_io(io, &fptr, 0, 1);
  watcher.fiber = Qnil;

  while (1) {
    backend->base.op_count++;
    ssize_t n = read(fd, ptr, len);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_READ);
      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = backend_snooze(&backend->base);

      if (IS_EXCEPTION(switchpoint_result)) goto error;

      if (n == 0) break; // EOF
      total = n;
      READ_LOOP_PASS_STR_TO_RECEIVER(receiver, method_id);
    }
  }

  RB_GC_GUARD(buffer);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return io;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_write(VALUE self, VALUE io, VALUE buffer) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;

  struct backend_buffer_spec buffer_spec = backend_get_buffer_spec(buffer, 1);
  long left = buffer_spec.len;

  fd = fd_from_io(io, &fptr, 1, 0);
  watcher.fiber = Qnil;

  while (left > 0) {
    backend->base.op_count++;
    ssize_t result = write(fd, buffer_spec.ptr, left);
    if (result < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_WRITE);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      buffer_spec.ptr += result;
      left -= result;
    }
  }

  if (watcher.fiber == Qnil) {
    switchpoint_result = backend_snooze(&backend->base);

    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2FIX(buffer_spec.len);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

#ifndef POLYPHONY_WINDOWS
VALUE Backend_writev(VALUE self, VALUE io, int argc, VALUE *argv) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;
  long total_length = 0;
  long total_written = 0;
  struct iovec *iov = 0;
  struct iovec *iov_ptr = 0;
  int iov_count = argc;

  fd = fd_from_io(io, &fptr, 1, 0);
  watcher.fiber = Qnil;

  iov = malloc(iov_count * sizeof(struct iovec));
  for (int i = 0; i < argc; i++) {
    VALUE buffer = argv[i];
    iov[i].iov_base = StringValuePtr(buffer);
    iov[i].iov_len = RSTRING_LEN(buffer);
    total_length += iov[i].iov_len;
  }
  iov_ptr = iov;

  while (1) {
    backend->base.op_count++;
    ssize_t n = writev(fd, iov_ptr, iov_count);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) {
        free(iov);
        rb_syserr_fail(e, strerror(e));
      }

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_WRITE);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
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
    switchpoint_result = backend_snooze(&backend->base);
    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  free(iov);
  return INT2FIX(total_written);
error:
  free(iov);
  return RAISE_EXCEPTION(switchpoint_result);
}
#endif

VALUE Backend_write_m(int argc, VALUE *argv, VALUE self) {
  if (argc < 2)
    // TODO: raise ArgumentError
    rb_raise(rb_eRuntimeError, "(wrong number of arguments (expected 2 or more))");

#ifdef POLYPHONY_WINDOWS
  int total = 0;
  for (int i = 1; i < argc; i++)
    total += FIX2INT(Backend_write(self, argv[0], argv[i]));
  return INT2FIX(total);
#else
  return (argc == 2) ?
    Backend_write(self, argv[0], argv[1]) :
    Backend_writev(self, argv[0], argc - 1, argv + 1);
#endif
}

VALUE Backend_accept(VALUE self, VALUE server_socket, VALUE socket_class) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int server_fd;
  rb_io_t *server_fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;

  server_fd = fd_from_io(server_socket, &server_fptr, 0, 0);
  watcher.fiber = Qnil;

  while (1) {
    backend->base.op_count++;
    fd = accept(server_fd, &addr, &len);
    if (fd < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, server_fd, &watcher, EV_READ);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      VALUE socket;
      rb_io_t *fp;
      switchpoint_result = backend_snooze(&backend->base);

      if (IS_EXCEPTION(switchpoint_result)) {
        close(fd); // close fd since we're raising an exception
        goto error;
      }

      socket = rb_obj_alloc(socket_class);
      MakeOpenFile(socket, fp);
      rb_update_max_fd(fd);
      fp->fd = fd;
      fp->mode = FMODE_READWRITE | FMODE_DUPLEX;
      rb_io_ascii8bit_binmode(socket);
      io_verify_blocking_mode(socket, fd, Qfalse);
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
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int server_fd;
  rb_io_t *server_fptr;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;
  VALUE socket = Qnil;

  server_fd = fd_from_io(server_socket, &server_fptr, 0, 0);
  watcher.fiber = Qnil;

  while (1) {
    backend->base.op_count++;
    int fd = accept(server_fd, &addr, &len);
    if (fd < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, server_fd, &watcher, EV_READ);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      rb_io_t *fp;
      switchpoint_result = backend_snooze(&backend->base);

      if (IS_EXCEPTION(switchpoint_result)) {
        close(fd); // close fd since we're raising an exception
        goto error;
      }

      socket = rb_obj_alloc(socket_class);
      MakeOpenFile(socket, fp);
      rb_update_max_fd(fd);
      fp->fd = fd;
      fp->mode = FMODE_READWRITE | FMODE_DUPLEX;
      rb_io_ascii8bit_binmode(socket);
      io_verify_blocking_mode(socket, fd, Qfalse);
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
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;
  struct sockaddr *ai_addr;
  int ai_addrlen;
  VALUE switchpoint_result = Qnil;

  ai_addrlen = backend_getaddrinfo(host, port, &ai_addr);

  fd = fd_from_io(sock, &fptr, 1, 0);
  watcher.fiber = Qnil;

  backend->base.op_count++;
  int result = connect(fd, ai_addr, ai_addrlen);
  if (result < 0) {
    int e = errno;
    if (e != EINPROGRESS) rb_syserr_fail(e, strerror(e));

    switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_WRITE);

    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }
  else {
    switchpoint_result = backend_snooze(&backend->base);

    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }
  RB_GC_GUARD(switchpoint_result);
  return sock;
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_send(VALUE self, VALUE io, VALUE buffer, VALUE flags) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;

  struct backend_buffer_spec buffer_spec = backend_get_buffer_spec(buffer, 1);
  long left = buffer_spec.len;
  int flags_int = FIX2INT(flags);

  fd = fd_from_io(io, &fptr, 1, 0);
  watcher.fiber = Qnil;

  while (left > 0) {
    backend->base.op_count++;
    ssize_t result = send(fd, buffer_spec.ptr, left, flags_int);
    if (result < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_WRITE);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      buffer_spec.ptr += result;
      left -= result;
    }
  }

  if (watcher.fiber == Qnil) {
    switchpoint_result = backend_snooze(&backend->base);

    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2FIX(buffer_spec.len);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_sendmsg(VALUE self, VALUE io, VALUE buffer, VALUE flags, VALUE dest_sockaddr, VALUE controls) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  int fd;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;

  struct backend_buffer_spec buffer_spec = backend_get_buffer_spec(buffer, 1);
  long left = buffer_spec.len;
  int flags_int = FIX2INT(flags);

  fd = fd_from_io(io, &fptr, 1, 0);
  watcher.fiber = Qnil;

  struct iovec iov;
  struct msghdr msg;

  iov.iov_base = buffer_spec.ptr;
  iov.iov_len = buffer_spec.len;

  if (dest_sockaddr != Qnil) {
    msg.msg_name = RSTRING_PTR(dest_sockaddr);
    msg.msg_namelen = RSTRING_LEN(dest_sockaddr);
  }
  else {
    msg.msg_name = 0;
    msg.msg_namelen = 0;
  }
  msg.msg_iov = &iov;
  msg.msg_iovlen = 1;
  msg.msg_control = 0;
  msg.msg_controllen = 0;
  msg.msg_flags = 0;

  while (left > 0) {
    backend->base.op_count++;
    ssize_t result = sendmsg(fd, &msg, flags_int);
    if (result < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_WRITE);

      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      iov.iov_base = (buffer_spec.ptr += result);
      iov.iov_len -= result;
      left -= result;
    }
  }

  if (watcher.fiber == Qnil) {
    switchpoint_result = backend_snooze(&backend->base);

    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2FIX(buffer_spec.len);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

struct libev_rw_ctx {
  int ref_count;
  VALUE fiber;
};

struct libev_ref_count_io {
  struct ev_io io;
  struct libev_rw_ctx *ctx;
};

struct libev_rw_io {
  struct libev_ref_count_io r;
  struct libev_ref_count_io w;
  struct libev_rw_ctx ctx;
};

void Backend_rw_io_callback(EV_P_ ev_io *w, int revents)
{
  struct libev_ref_count_io *watcher = (struct libev_ref_count_io *)w;
  int ref_count = watcher->ctx->ref_count--;
  if (!ref_count)
    Fiber_make_runnable(watcher->ctx->fiber, Qnil);
}

VALUE libev_wait_rw_fd_with_watcher(Backend_t *backend, int r_fd, int w_fd, struct libev_rw_io *watcher) {
  VALUE switchpoint_result = Qnil;

  if (watcher->ctx.fiber == Qnil) watcher->ctx.fiber = rb_fiber_current();
  watcher->ctx.ref_count = 0;
  if (r_fd != -1) {
    ev_io_init(&watcher->r.io, Backend_rw_io_callback, r_fd, EV_READ);
    ev_io_start(backend->ev_loop, &watcher->r.io);
    watcher->r.ctx = &watcher->ctx;
    watcher->ctx.ref_count++;
  }
  if (w_fd != -1) {
    ev_io_init(&watcher->w.io, Backend_rw_io_callback, w_fd, EV_WRITE);
    ev_io_start(backend->ev_loop, &watcher->w.io);
    watcher->w.ctx = &watcher->ctx;
    watcher->ctx.ref_count++;
  }

  switchpoint_result = backend_await((struct Backend_base *)backend);

  if (r_fd != -1) ev_io_stop(backend->ev_loop, &watcher->r.io);
  if (w_fd != -1) ev_io_stop(backend->ev_loop, &watcher->w.io);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

#ifdef POLYPHONY_LINUX
VALUE Backend_splice(VALUE self, VALUE src, VALUE dest, VALUE maxlen) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_rw_io watcher;
  VALUE switchpoint_result = Qnil;
  int src_fd;
  int dest_fd;
  rb_io_t *src_fptr;
  rb_io_t *dest_fptr;
  int len;
  int total = 0;
  int maxlen_i = FIX2INT(maxlen);
  int splice_to_eof = maxlen_i < 0;
  if (splice_to_eof) maxlen_i = -maxlen_i;

  src_fd = fd_from_io(src, &src_fptr, 0, 0);
  dest_fd = fd_from_io(dest, &dest_fptr, 1, 0);
  watcher.ctx.fiber = Qnil;

  while (1) {
    backend->base.op_count++;
    len = splice(src_fd, 0, dest_fd, 0, maxlen_i, 0);
    if (len < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_rw_fd_with_watcher(backend, src_fd, dest_fd, &watcher);
      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      total += len;
      if (!len || !splice_to_eof) break;
    }
  }

  if (watcher.ctx.fiber == Qnil) {
    switchpoint_result = backend_snooze(&backend->base);
    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.ctx.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2FIX(total);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_tee(VALUE self, VALUE src, VALUE dest, VALUE maxlen) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_rw_io watcher;
  VALUE switchpoint_result = Qnil;
  int src_fd;
  int dest_fd;
  rb_io_t *src_fptr;
  rb_io_t *dest_fptr;
  int len;

  src_fd = fd_from_io(src, &src_fptr, 0, 0);
  dest_fd = fd_from_io(dest, &dest_fptr, 1, 0);
  watcher.ctx.fiber = Qnil;

  while (1) {
    backend->base.op_count++;
    len = tee(src_fd, dest_fd, FIX2INT(maxlen), 0);
    if (len < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_wait_rw_fd_with_watcher(backend, src_fd, dest_fd, &watcher);
      if (IS_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      break;
    }
  }

  if (watcher.ctx.fiber == Qnil) {
    switchpoint_result = backend_snooze(&backend->base);
    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.ctx.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2FIX(len);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}
#else
VALUE Backend_splice(VALUE self, VALUE src, VALUE dest, VALUE maxlen) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_io watcher;
  VALUE switchpoint_result = Qnil;
  int src_fd;
  int dest_fd;
  rb_io_t *src_fptr;
  rb_io_t *dest_fptr;
  int left = 0;
  int total = 0;
  char *ptr;
  int maxlen_i = FIX2INT(maxlen);
  int splice_to_eof = maxlen_i < 0;
  if (splice_to_eof) maxlen_i = -maxlen_i;
  VALUE buffer = rb_str_new(0, maxlen_i);

  src_fd = fd_from_io(src, &src_fptr, 0, 0);
  dest_fd = fd_from_io(dest, &dest_fptr, 1, 0);
  watcher.fiber = Qnil;

  while (1) {
    int done;
    while (1) {
      backend->base.op_count++;
      ptr = RSTRING_PTR(buffer);
      ssize_t n = read(src_fd, ptr, maxlen_i);
      if (n < 0) {
        int e = errno;
        if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

        switchpoint_result = libev_wait_fd_with_watcher(backend, src_fd, &watcher, EV_READ);
        if (IS_EXCEPTION(switchpoint_result)) goto error;
      }
      else {
        total += left = n;
        done = !n || !splice_to_eof;
        break;
      }
    }

    while (left > 0) {
      backend->base.op_count++;
      ssize_t n = write(dest_fd, ptr, left);
      if (n < 0) {
        int e = errno;
        if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

        switchpoint_result = libev_wait_fd_with_watcher(backend, dest_fd, &watcher, EV_WRITE);

        if (IS_EXCEPTION(switchpoint_result)) goto error;
      }
      else {
        ptr += n;
        left -= n;
      }
    }
    if (done) break;
  }

  if (watcher.fiber == Qnil) {
    switchpoint_result = backend_snooze(&backend->base);
    if (IS_EXCEPTION(switchpoint_result)) goto error;
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  RB_GC_GUARD(buffer);

  return INT2FIX(total);
error:
  return RAISE_EXCEPTION(switchpoint_result);
}

VALUE Backend_tee(VALUE self, VALUE src, VALUE dest, VALUE maxlen) {
  return self;
}
#endif

VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  int fd;
  rb_io_t *fptr;
  int write_mode = RTEST(write);
  int events = write_mode ? EV_WRITE : EV_READ;
  fd = fd_from_io(io, &fptr, write_mode, 0);

  backend->base.op_count++;
  return libev_wait_fd(backend, fd, events, 1);
}

VALUE Backend_close(VALUE self, VALUE io) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  rb_io_t *fptr;
  VALUE resume_value = Qnil;
  int result;
  int fd = fd_from_io(io, &fptr, 0, 0);
  if (fd < 0) return Qnil;

  result = close(fd);
  if (result == -1) {
    int err = errno;
    rb_syserr_fail(err, strerror(err));
  }

  resume_value = backend_snooze(&backend->base);
  RAISE_IF_EXCEPTION(resume_value);
  RB_GC_GUARD(resume_value);

  if (fptr) fptr_finalize(fptr);
  // fd = -1;
  return io;
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
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_timer watcher;
  VALUE switchpoint_result = Qnil;

  watcher.fiber = rb_fiber_current();
  ev_timer_init(&watcher.timer, Backend_timer_callback, NUM2DBL(duration), 0.);
  ev_timer_start(backend->ev_loop, &watcher.timer);
  backend->base.op_count++;

  switchpoint_result = backend_await((struct Backend_base *)backend);

  ev_timer_stop(backend->ev_loop, &watcher.timer);
  RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

noreturn VALUE Backend_timer_loop(VALUE self, VALUE interval) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_timer watcher;
  watcher.fiber = rb_fiber_current();
  uint64_t interval_ns = NUM2DBL(interval) * 1e9;
  uint64_t next_time_ns = 0;
  VALUE resume_value = Qnil;

  while (1) {
    uint64_t now_ns = current_time_ns();
    if (next_time_ns == 0) next_time_ns = now_ns + interval_ns;

    if (next_time_ns > now_ns) {
      double sleep_duration = ((double)(next_time_ns - now_ns))/1e9;
      ev_timer_init(&watcher.timer, Backend_timer_callback, sleep_duration, 0.);
      ev_timer_start(backend->ev_loop, &watcher.timer);
      backend->base.op_count++;
      resume_value = backend_await((struct Backend_base *)backend);
      ev_timer_stop(backend->ev_loop, &watcher.timer);
      RAISE_IF_EXCEPTION(resume_value);
    }
    else {
      resume_value = backend_snooze(&backend->base);
      RAISE_IF_EXCEPTION(resume_value);
    }

    rb_yield(Qnil);

    while (1) {
      next_time_ns += interval_ns;
      if (next_time_ns > now_ns) break;
    }
  }
  RB_GC_GUARD(resume_value);
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

  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_timeout watcher;
  VALUE result = Qnil;
  VALUE timeout = rb_funcall(cTimeoutException, ID_new, 0);

  watcher.fiber = rb_fiber_current();
  watcher.resume_value = timeout;
  ev_timer_init(&watcher.timer, Backend_timeout_callback, NUM2DBL(duration), 0.);
  ev_timer_start(backend->ev_loop, &watcher.timer);
  backend->base.op_count++;

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
  int pid_int = FIX2INT(pid);
  int fd = pidfd_open(pid_int, 0);
  if (fd >= 0) {
    Backend_t *backend = RTYPEDDATA_DATA(self);
    backend->base.op_count++;

    VALUE resume_value = libev_wait_fd(backend, fd, EV_READ, 0);
    close(fd);
    RAISE_IF_EXCEPTION(resume_value);
    RB_GC_GUARD(resume_value);
  }
  else {
    int e = errno;
    rb_syserr_fail(e, strerror(e));
  }

  int status = 0;
  pid_t ret = waitpid(pid_int, &status, WNOHANG);
  if (ret < 0) {
    int e = errno;
    rb_syserr_fail(e, strerror(e));
  }
  return rb_ary_new_from_args(2, INT2FIX(ret), INT2FIX(status));
}
#else
struct libev_child {
  struct ev_child child;
  VALUE fiber;
};

#ifndef POLYPHONY_WINDOWS
void Backend_child_callback(EV_P_ ev_child *w, int revents) {
  struct libev_child *watcher = (struct libev_child *)w;
  VALUE status = rb_ary_new_from_args(2, INT2FIX(w->rpid), INT2FIX(w->rstatus));
  Fiber_make_runnable(watcher->fiber, status);
}
#endif

VALUE Backend_waitpid(VALUE self, VALUE pid) {
#ifdef POLYPHONY_WINDOWS
  rb_raise(rb_eStandardError, "Not implemented");
#else
  Backend_t *backend = RTYPEDDATA_DATA(self);
  struct libev_child watcher;
  VALUE switchpoint_result = Qnil;

  watcher.fiber = rb_fiber_current();
  ev_child_init(&watcher.child, Backend_child_callback, FIX2INT(pid), 0);
  ev_child_start(backend->ev_loop, &watcher.child);
  backend->base.op_count++;

  switchpoint_result = backend_await((struct Backend_base *)backend);

  ev_child_stop(backend->ev_loop, &watcher.child);
  RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
#endif // #ifdef POLYPHONY_WINDOWS
}
#endif // #ifdef POLYPHONY_USE_PIDFD_OPEN

void Backend_async_callback(EV_P_ ev_async *w, int revents) { }

VALUE Backend_wait_event(VALUE self, VALUE raise) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  VALUE switchpoint_result = Qnil;

  struct ev_async async;

  ev_async_init(&async, Backend_async_callback);
  ev_async_start(backend->ev_loop, &async);
  backend->base.op_count++;

  switchpoint_result = backend_await((struct Backend_base *)backend);

  ev_async_stop(backend->ev_loop, &async);
  if (RTEST(raise)) RAISE_IF_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

VALUE Backend_kind(VALUE self) {
  return SYM_libev;
}

VALUE Backend_chain(int argc,VALUE *argv, VALUE self) {
  VALUE result = Qnil;
  if (argc == 0) return result;

  for (int i = 0; i < argc; i++) {
    VALUE op = argv[i];
    VALUE op_type = RARRAY_AREF(op, 0);
    VALUE op_len = RARRAY_LEN(op);

    if (op_type == SYM_write && op_len == 3)
      result = Backend_write(self, RARRAY_AREF(op, 1), RARRAY_AREF(op, 2));
    else if (op_type == SYM_send && op_len == 4)
      result = Backend_send(self, RARRAY_AREF(op, 1), RARRAY_AREF(op, 2), RARRAY_AREF(op, 3));
    else if (op_type == SYM_splice && op_len == 4)
      result = Backend_splice(self, RARRAY_AREF(op, 1), RARRAY_AREF(op, 2), RARRAY_AREF(op, 3));
    else
      rb_raise(rb_eRuntimeError, "Invalid op specified or bad op arity");
  }

  RB_GC_GUARD(result);
  return result;
}

VALUE Backend_idle_gc_period_set(VALUE self, VALUE period) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend->base.idle_gc_period = NUM2DBL(period);
  backend->base.idle_gc_last_time = current_time();
  return self;
}

VALUE Backend_idle_proc_set(VALUE self, VALUE block) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend->base.idle_proc = block;
  return self;
}

inline VALUE Backend_run_idle_tasks(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend_run_idle_tasks(&backend->base);
  return self;
}

static inline int splice_chunks_write(Backend_t *backend, int fd, VALUE buffer, struct libev_rw_io *watcher, VALUE *result) {
  char *ptr = RSTRING_PTR(buffer);
  int len = RSTRING_LEN(buffer);
  int left = len;
  while (left > 0) {
    backend->base.op_count++;
    ssize_t n = write(fd, ptr, left);
    if (n < 0) {
      int err = errno;
      if ((err != EWOULDBLOCK && err != EAGAIN)) return err;

      *result = libev_wait_rw_fd_with_watcher(backend, -1, fd, watcher);
      if (IS_EXCEPTION(*result)) return -1;
    }
    else {
      ptr += n;
      left -= n;
    }
  }
  return 0;
}

static inline int splice_chunks_splice(Backend_t *backend, int src_fd, int dest_fd, int maxlen,
  struct libev_rw_io *watcher, VALUE *result, int *chunk_len) {
#ifdef POLYPHONY_LINUX
  backend->base.op_count++;
  while (1) {
    *chunk_len = splice(src_fd, 0, dest_fd, 0, maxlen, 0);
    if (*chunk_len >= 0) return 0;

    int err = errno;
    if (err != EWOULDBLOCK && err != EAGAIN) return err;

    *result = libev_wait_rw_fd_with_watcher(backend, src_fd, dest_fd, watcher);
    if (IS_EXCEPTION(*result)) return -1;
  }
#else
  char *buf = malloc(maxlen);
  int ret;

  backend->base.op_count++;
  while (1) {
    *chunk_len = read(src_fd, buf, maxlen);
    if (*chunk_len >= 0) break;

    ret = errno;
    if ((ret != EWOULDBLOCK && ret != EAGAIN)) goto done;

    *result = libev_wait_rw_fd_with_watcher(backend, src_fd, -1, watcher);
    if (IS_EXCEPTION(*result)) goto exception;
  }

  backend->base.op_count++;
  char *ptr = buf;
  int left = *chunk_len;
  while (left > 0) {
    ssize_t n = write(dest_fd, ptr, left);
    if (n < 0) {
      ret = errno;
      if ((ret != EWOULDBLOCK && ret != EAGAIN)) goto done;

      *result = libev_wait_rw_fd_with_watcher(backend, -1, dest_fd, watcher);

      if (IS_EXCEPTION(*result)) goto exception;
    }
    else {
      ptr += n;
      left -= n;
    }
  }
  ret = 0;
  goto done;
exception:
  ret = -1;
done:
  free(buf);
  return ret;
#endif
}

#ifdef POLYPHONY_LINUX
VALUE Backend_splice_chunks(VALUE self, VALUE src, VALUE dest, VALUE prefix, VALUE postfix, VALUE chunk_prefix, VALUE chunk_postfix, VALUE chunk_size) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  int total = 0;
  int err = 0;
  VALUE result = Qnil;

  int src_fd;
  int dest_fd;
  rb_io_t *src_fptr;
  rb_io_t *dest_fptr;

  src_fd = fd_from_io(src, &src_fptr, 0, 0);
  dest_fd = fd_from_io(dest, &dest_fptr, 1, 0);

  struct libev_rw_io watcher;
  watcher.ctx.fiber = Qnil;
  int maxlen = FIX2INT(chunk_size);
  VALUE chunk_len_value = Qnil;
  VALUE buffer;

  int pipefd[2] = { -1, -1 };
  if (pipe(pipefd) == -1) {
    err = errno;
    goto syscallerror;
  }

  fcntl(pipefd[0], F_SETFL, O_NONBLOCK);
  fcntl(pipefd[1], F_SETFL, O_NONBLOCK);

  if (prefix != Qnil) {
    err = splice_chunks_write(backend, dest_fd, prefix, &watcher, &result);
    if (err == -1) goto error; else if (err) goto syscallerror;
  }
  while (1) {
    int chunk_len = 0;
    err = splice_chunks_splice(backend, src_fd, pipefd[1], maxlen, &watcher, &result, &chunk_len);
    if (err == -1) goto error; else if (err) goto syscallerror;
    if (chunk_len == 0) break;

    total += chunk_len;
    chunk_len_value = INT2FIX(chunk_len);

    if (chunk_prefix != Qnil) {
      buffer = (TYPE(chunk_prefix) == T_STRING) ? chunk_prefix : rb_funcall(chunk_prefix, ID_call, 1, chunk_len_value);
      int err = splice_chunks_write(backend, dest_fd, buffer, &watcher, &result);
      if (err == -1) goto error; else if (err) goto syscallerror;
    }

    int left = chunk_len;
    while (left > 0) {
      int len;
      err = splice_chunks_splice(backend, pipefd[0], dest_fd, left, &watcher, &result, &len);
      if (err == -1) goto error; else if (err) goto syscallerror;

      left -= len;
    }

    if (chunk_postfix != Qnil) {
      buffer = (TYPE(chunk_postfix) == T_STRING) ? chunk_postfix : rb_funcall(chunk_postfix, ID_call, 1, chunk_len_value);
      int err = splice_chunks_write(backend, dest_fd, buffer, &watcher, &result);
      if (err == -1) goto error; else if (err) goto syscallerror;
    }
  }

  if (postfix != Qnil) {
    int err = splice_chunks_write(backend, dest_fd, postfix, &watcher, &result);
    if (err == -1) goto error; else if (err) goto syscallerror;
  }

  if (watcher.ctx.fiber == Qnil) {
    result = backend_snooze(&backend->base);
    if (IS_EXCEPTION(result)) goto error;
  }
  RB_GC_GUARD(buffer);
  RB_GC_GUARD(chunk_len_value);
  RB_GC_GUARD(result);
  if (pipefd[0] != -1) close(pipefd[0]);
  if (pipefd[1] != -1) close(pipefd[1]);
  return INT2FIX(total);
syscallerror:
  if (pipefd[0] != -1) close(pipefd[0]);
  if (pipefd[1] != -1) close(pipefd[1]);
  rb_syserr_fail(err, strerror(err));
error:
  if (pipefd[0] != -1) close(pipefd[0]);
  if (pipefd[1] != -1) close(pipefd[1]);
  return RAISE_EXCEPTION(result);
}
#endif

VALUE Backend_trace(int argc, VALUE *argv, VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend_trace(&backend->base, argc, argv);
  return self;
}

VALUE Backend_trace_proc_set(VALUE self, VALUE block) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend->base.trace_proc = block;
  return self;
}

VALUE Backend_snooze(VALUE self) {
  Backend_t *backend = RTYPEDDATA_DATA(self);
  VALUE ret;
  VALUE fiber = rb_fiber_current();

  Fiber_make_runnable(fiber, Qnil);
  ret = backend_base_switch_fiber(self, &backend->base);

  COND_TRACE(&backend->base, 4, SYM_unblock, rb_fiber_current(), ret, CALLER());

  RAISE_IF_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

void Backend_park_fiber(VALUE self, VALUE fiber) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend_base_park_fiber(&backend->base, fiber);
}

void Backend_unpark_fiber(VALUE self, VALUE fiber) {
  Backend_t *backend = RTYPEDDATA_DATA(self);

  backend_base_unpark_fiber(&backend->base, fiber);
}

VALUE Backend_stream_read(VALUE self, VALUE io, buffer_descriptor *desc, int len, int *result)
{
  Backend_t *backend = RTYPEDDATA_DATA(self);
  rb_io_t *fptr;
  int fd = fd_from_io(io, &fptr, 0, 1);
  VALUE switchpoint_result = Qnil;
  struct libev_io watcher;

  watcher.fiber = Qnil;
  while (1) {
    backend->base.op_count++;
    ssize_t ret = read(fd, desc->ptr, len);
    if (ret < 0) {
      int e = errno;
      if (e != EWOULDBLOCK && e != EAGAIN) {
        *result = -e;
        break;
      }

      switchpoint_result = libev_wait_fd_with_watcher(backend, fd, &watcher, EV_READ);

      if (IS_EXCEPTION(switchpoint_result)) return switchpoint_result;
    }
    else {
      switchpoint_result = backend_snooze(&backend->base);
      if (IS_EXCEPTION(switchpoint_result)) return switchpoint_result;

      *result = desc->len = ret;
      break;
    }
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return Qtrue;
}

void Init_Backend(void) {
  ev_set_allocator(xrealloc);

  cBackend = rb_define_class_under(mPolyphony, "Backend", rb_cObject);
  rb_define_alloc_func(cBackend, Backend_allocate);

  rb_define_method(cBackend, "initialize", Backend_initialize, 0);
  rb_define_method(cBackend, "finalize", Backend_finalize, 0);
  rb_define_method(cBackend, "post_fork", Backend_post_fork, 0);
  rb_define_method(cBackend, "trace", Backend_trace, -1);
  rb_define_method(cBackend, "trace_proc=", Backend_trace_proc_set, 1);
  rb_define_method(cBackend, "stats", Backend_stats, 0);

  rb_define_method(cBackend, "poll", Backend_poll, 1);
  rb_define_method(cBackend, "break", Backend_wakeup, 0);
  rb_define_method(cBackend, "kind", Backend_kind, 0);
  rb_define_method(cBackend, "chain", Backend_chain, -1);
  rb_define_method(cBackend, "idle_gc_period=", Backend_idle_gc_period_set, 1);
  rb_define_method(cBackend, "idle_proc=", Backend_idle_proc_set, 1);

  #ifdef POLYPHONY_LINUX
  rb_define_method(cBackend, "splice_chunks", Backend_splice_chunks, 7);
  #endif

  rb_define_method(cBackend, "accept", Backend_accept, 2);
  rb_define_method(cBackend, "accept_loop", Backend_accept_loop, 2);
  rb_define_method(cBackend, "connect", Backend_connect, 3);
  rb_define_method(cBackend, "feed_loop", Backend_feed_loop, 3);
  rb_define_method(cBackend, "read", Backend_read, 5);
  rb_define_method(cBackend, "read_loop", Backend_read_loop, 2);
  rb_define_method(cBackend, "recv", Backend_recv, 4);
  rb_define_method(cBackend, "recvmsg", Backend_recvmsg, 7);
  rb_define_method(cBackend, "recv_loop", Backend_read_loop, 2);
  rb_define_method(cBackend, "recv_feed_loop", Backend_feed_loop, 3);
  rb_define_method(cBackend, "send", Backend_send, 3);
  rb_define_method(cBackend, "sendmsg", Backend_sendmsg, 5);
  rb_define_method(cBackend, "sendv", Backend_sendv, 3);
  rb_define_method(cBackend, "sleep", Backend_sleep, 1);

  rb_define_method(cBackend, "splice", Backend_splice, 3);
  #ifdef POLYPHONY_LINUX
  rb_define_method(cBackend, "tee", Backend_tee, 3);
  #endif

  rb_define_method(cBackend, "timeout", Backend_timeout, -1);
  rb_define_method(cBackend, "timer_loop", Backend_timer_loop, 1);
  rb_define_method(cBackend, "wait_event", Backend_wait_event, 1);
  rb_define_method(cBackend, "wait_io", Backend_wait_io, 2);
  rb_define_method(cBackend, "waitpid", Backend_waitpid, 1);
  rb_define_method(cBackend, "write", Backend_write_m, -1);
  rb_define_method(cBackend, "close", Backend_close, 1);

  SYM_libev = ID2SYM(rb_intern("libev"));

  SYM_send = ID2SYM(rb_intern("send"));
  SYM_splice = ID2SYM(rb_intern("splice"));
  SYM_write = ID2SYM(rb_intern("write"));

  backend_setup_stats_symbols();
}

#endif // POLYPHONY_BACKEND_LIBEV
