#ifdef POLYPHONY_BACKEND_LIBEV

#include <netdb.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "polyphony.h"
#include "../libev/ev.h"
#include "ruby/io.h"

VALUE cTCPSocket;

typedef struct Backend_t {
  struct ev_loop *ev_loop;
  struct ev_async break_async;
  int running;
  int ref_count;
  int run_no_wait_count;
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

  backend->running = 0;
  backend->ref_count = 0;
  backend->run_no_wait_count = 0;

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
  int count;
  Backend_t *backend;
  GetBackend(self, backend);
  count = ev_pending_count(backend->ev_loop);
  return INT2NUM(count);
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
  ev_run(backend->ev_loop, is_nowait ? EVRUN_NOWAIT : EVRUN_ONCE);
  backend->running = 0;
  COND_TRACE(2, SYM_backend_poll_leave, current_fiber);

  return self;
}

VALUE Backend_wakeup(VALUE self) {
  Backend_t *backend;
  GetBackend(self, backend);

  if (backend->running) {
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

  if (raise_exception) TEST_RESUME_EXCEPTION(switchpoint_result);
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
  VALUE underlying_io = rb_iv_get(io, "@io");

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
  VALUE underlying_io = rb_iv_get(io, "@io");

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

VALUE Backend_write(VALUE self, VALUE io, VALUE str) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_io;
  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;

  underlying_io = rb_iv_get(io, "@io");
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

  underlying_io = rb_iv_get(io, "@io");
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

VALUE Backend_accept(VALUE self, VALUE sock) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_sock = rb_iv_get(sock, "@io");
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetBackend(self, backend);
  GetOpenFile(sock, fptr);
  io_set_nonblock(fptr, sock);
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

      socket = rb_obj_alloc(cTCPSocket);
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

VALUE Backend_accept_loop(VALUE self, VALUE sock) {
  Backend_t *backend;
  struct libev_io watcher;
  rb_io_t *fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;
  VALUE socket = Qnil;
  VALUE underlying_sock = rb_iv_get(sock, "@io");
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetBackend(self, backend);
  GetOpenFile(sock, fptr);
  io_set_nonblock(fptr, sock);
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

      socket = rb_obj_alloc(cTCPSocket);
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
  VALUE underlying_sock = rb_iv_get(sock, "@io");
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

VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write) {
  Backend_t *backend;
  rb_io_t *fptr;
  int events = RTEST(write) ? EV_WRITE : EV_READ;
  VALUE underlying_io = rb_iv_get(io, "@io");
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
  TEST_RESUME_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

struct libev_child {
  struct ev_child child;
  VALUE fiber;
};

void Backend_child_callback(EV_P_ ev_child *w, int revents)
{
  struct libev_child *watcher = (struct libev_child *)w;
  int exit_status = w->rstatus >> 8; // weird, why should we do this?
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
  TEST_RESUME_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

VALUE Backend_wait_event(VALUE self, VALUE raise) {
  Backend_t *backend;
  VALUE switchpoint_result = Qnil;
  GetBackend(self, backend);

  struct ev_async async;

  ev_async_init(&async, Backend_async_callback);
  ev_async_start(backend->ev_loop, &async);

  switchpoint_result = backend_await(backend);

  ev_async_stop(backend->ev_loop, &async);
  if (RTEST(raise)) TEST_RESUME_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

void Init_Backend() {
  ev_set_allocator(xrealloc);

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

  ID_ivar_is_nonblocking = rb_intern("@is_nonblocking");

  __BACKEND__.pending_count   = Backend_pending_count;
  __BACKEND__.poll            = Backend_poll;
  __BACKEND__.ref             = Backend_ref;
  __BACKEND__.ref_count       = Backend_ref_count;
  __BACKEND__.reset_ref_count = Backend_reset_ref_count;
  __BACKEND__.unref           = Backend_unref;
  __BACKEND__.wait_event      = Backend_wait_event;
  __BACKEND__.wakeup          = Backend_wakeup;
}

#endif // POLYPHONY_BACKEND_LIBEV
