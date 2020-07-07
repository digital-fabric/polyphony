#include <netdb.h>
#include <sys/socket.h>

#include "polyphony.h"
#include "../libev/ev.h"

VALUE cLibevAgent = Qnil;
VALUE cTCPSocket;

struct LibevAgent_t {
  struct ev_loop *ev_loop;
  struct ev_async break_async;
  int running;
  int ref_count;
  int run_no_wait_count;
};

static size_t LibevAgent_size(const void *ptr) {
  return sizeof(struct LibevAgent_t);
}

static const rb_data_type_t LibevAgent_type = {
    "Libev",
    {0, 0, LibevAgent_size,},
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE LibevAgent_allocate(VALUE klass) {
  struct LibevAgent_t *agent = ALLOC(struct LibevAgent_t);
  
  return TypedData_Wrap_Struct(klass, &LibevAgent_type, agent);
}

#define GetLibevAgent(obj, agent) \
  TypedData_Get_Struct((obj), struct LibevAgent_t, &LibevAgent_type, (agent))

void break_async_callback(struct ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  // This callback does nothing, the break async is used solely for breaking out
  // of a *blocking* event loop (waking it up) in a thread-safe, signal-safe manner
}

static VALUE LibevAgent_initialize(VALUE self) {
  struct LibevAgent_t *agent;
  VALUE thread = rb_thread_current();
  int is_main_thread = (thread == rb_thread_main());

  GetLibevAgent(self, agent);
  agent->ev_loop = is_main_thread ? EV_DEFAULT : ev_loop_new(EVFLAG_NOSIGMASK);

  ev_async_init(&agent->break_async, break_async_callback);
  ev_async_start(agent->ev_loop, &agent->break_async);
  ev_unref(agent->ev_loop); // don't count the break_async watcher

  agent->running = 0;
  agent->ref_count = 0;
  agent->run_no_wait_count = 0;

  return Qnil;
}

VALUE LibevAgent_finalize(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

   ev_async_stop(agent->ev_loop, &agent->break_async);

  if (!ev_is_default_loop(agent->ev_loop)) ev_loop_destroy(agent->ev_loop);

  return self;
}

VALUE LibevAgent_post_fork(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

  if (!ev_is_default_loop(agent->ev_loop)) {
    // post_fork is called only for the main thread of the forked process. If
    // the forked process was forked from a thread other than the main one,
    // we remove the old non-default ev_loop and use the default one instead.
    ev_loop_destroy(agent->ev_loop);
    agent->ev_loop = EV_DEFAULT;
  }

  ev_loop_fork(agent->ev_loop);

  return self;
}

VALUE LibevAgent_ref(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

  agent->ref_count++;
  return self;  
}

VALUE LibevAgent_unref(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

  agent->ref_count--;
  return self;  
}

int LibevAgent_ref_count(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

  return agent->ref_count;
}

void LibevAgent_reset_ref_count(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

  agent->ref_count = 0;
}

VALUE LibevAgent_pending_count(VALUE self) {
  int count;
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);
  count = ev_pending_count(agent->ev_loop);
  return INT2NUM(count);
}

VALUE LibevAgent_poll(VALUE self, VALUE nowait, VALUE current_fiber, VALUE queue) {
  int is_nowait = nowait == Qtrue;
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

  if (is_nowait) {
    long runnable_count = RARRAY_LEN(queue);
    agent->run_no_wait_count++;
    if (agent->run_no_wait_count < runnable_count || agent->run_no_wait_count < 10)
      return self;
  }

  agent->run_no_wait_count = 0;
  
  FIBER_TRACE(2, SYM_fiber_ev_loop_enter, current_fiber);
  agent->running = 1;
  ev_run(agent->ev_loop, is_nowait ? EVRUN_NOWAIT : EVRUN_ONCE);
  agent->running = 0;
  FIBER_TRACE(2, SYM_fiber_ev_loop_leave, current_fiber);

  return self;
}

VALUE LibevAgent_break(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);

  if (agent->running) {
    // Since the loop will run until at least one event has occurred, we signal
    // the selector's associated async watcher, which will cause the ev loop to
    // return. In contrast to using `ev_break` to break out of the loop, which
    // should be called from the same thread (from within the ev_loop), using an
    // `ev_async` allows us to interrupt the event loop across threads.
    ev_async_send(agent->ev_loop, &agent->break_async);
    return Qtrue;
  }

  return Qnil;
}

#include "polyphony.h"
#include "../libev/ev.h"

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////
// the following is copied verbatim from the Ruby source code (io.c)
struct io_internal_read_struct {
    int fd;
    int nonblock;
    void *buf;
    size_t capa;
};

#define StringValue(v) rb_string_value(&(v))

int io_setstrbuf(VALUE *str, long len) {
  #ifdef _WIN32
    len = (len + 1) & ~1L;	/* round up for wide char */
  #endif
  if (NIL_P(*str)) {
    *str = rb_str_new(0, len);
    return 1;
  }
  else {
    VALUE s = StringValue(*str);
    long clen = RSTRING_LEN(s);
    if (clen >= len) {
      rb_str_modify(s);
      return 0;
    }
    len -= clen;
  }
  rb_str_modify_expand(*str, len);
  return 0;
}

#define MAX_REALLOC_GAP 4096
static void io_shrink_read_string(VALUE str, long n) {
  if (rb_str_capacity(str) - n > MAX_REALLOC_GAP) {
    rb_str_resize(str, n);
  }
}

void io_set_read_length(VALUE str, long n, int shrinkable) {
  if (RSTRING_LEN(str) != n) {
    rb_str_modify(str);
    rb_str_set_len(str, n);
    if (shrinkable) io_shrink_read_string(str, n);
  }
}

static rb_encoding* io_read_encoding(rb_io_t *fptr) {
    if (fptr->encs.enc) {
	return fptr->encs.enc;
    }
    return rb_default_external_encoding();
}

VALUE io_enc_str(VALUE str, rb_io_t *fptr) {
    OBJ_TAINT(str);
    rb_enc_associate(str, io_read_encoding(fptr));
    return str;
}

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////

struct libev_io {
  struct ev_io io;
  VALUE fiber;
};

void LibevAgent_io_callback(EV_P_ ev_io *w, int revents)
{
  struct libev_io *watcher = (struct libev_io *)w;
  Fiber_make_runnable(watcher->fiber, Qnil);
}

inline VALUE libev_await(struct LibevAgent_t *agent) {
  VALUE ret;
  agent->ref_count++;
  ret = Thread_switch_fiber(rb_thread_current());
  agent->ref_count--;
  RB_GC_GUARD(ret);
  return ret;
}

VALUE libev_agent_await(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);
  return libev_await(agent);
}

VALUE libev_io_wait(struct LibevAgent_t *agent, struct libev_io *watcher, rb_io_t *fptr, int flags) {
  VALUE switchpoint_result;

  if (watcher->fiber == Qnil) {
    watcher->fiber = rb_fiber_current();
    ev_io_init(&watcher->io, LibevAgent_io_callback, fptr->fd, flags);
  }
  ev_io_start(agent->ev_loop, &watcher->io);
  switchpoint_result = libev_await(agent);
  ev_io_stop(agent->ev_loop, &watcher->io);

  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;  
}

VALUE libev_snooze() {
  Fiber_make_runnable(rb_fiber_current(), Qnil);
  return Thread_switch_fiber(rb_thread_current());
}

VALUE LibevAgent_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof) {
  struct LibevAgent_t *agent;
  struct libev_io watcher;
  rb_io_t *fptr;
  long len = NUM2INT(length);
  int shrinkable = io_setstrbuf(&str, len);
  char *buf = RSTRING_PTR(str);
  long total = 0;
  VALUE switchpoint_result = Qnil;
  int read_to_eof = RTEST(to_eof);
  VALUE underlying_io = rb_iv_get(io, "@io");

  GetLibevAgent(self, agent);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  rb_io_set_nonblock(fptr);
  watcher.fiber = Qnil;
  
  OBJ_TAINT(str);

  while (len > 0) {
    ssize_t n = read(fptr->fd, buf, len);
    if (n < 0) {
      int e = errno;
      if (e != EWOULDBLOCK && e != EAGAIN) rb_syserr_fail(e, strerror(e));
      
      switchpoint_result = libev_io_wait(agent, &watcher, fptr, EV_READ);
      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = libev_snooze();
      if (TEST_EXCEPTION(switchpoint_result)) goto error;

      if (n == 0) break; // EOF

      total = total + n;
      buf += n;
      len -= n;
      if (!read_to_eof || (len == 0)) break;
    }
  }

  if (total == 0) return Qnil;

  io_set_read_length(str, total, shrinkable);
  io_enc_str(str, fptr);
  
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return str;
error:
  return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
}

VALUE LibevAgent_read_loop(VALUE self, VALUE io) {

  #define PREPARE_STR() { \
    str = Qnil; \
    shrinkable = io_setstrbuf(&str, len); \
    buf = RSTRING_PTR(str); \
    total = 0; \
  }

  #define YIELD_STR() { \
    io_set_read_length(str, total, shrinkable); \
    io_enc_str(str, fptr); \
    rb_yield(str); \
    PREPARE_STR(); \
  }

  struct LibevAgent_t *agent;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE str;
  long total;
  long len = 8192;
  int shrinkable;
  char *buf;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_io = rb_iv_get(io, "@io");

  PREPARE_STR();

  GetLibevAgent(self, agent);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  rb_io_set_nonblock(fptr);
  watcher.fiber = Qnil;

  OBJ_TAINT(str);

  while (1) {
    ssize_t n = read(fptr->fd, buf, len);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_io_wait(agent, &watcher, fptr, EV_READ);
      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = libev_snooze();
      if (TEST_EXCEPTION(switchpoint_result)) goto error;

      if (n == 0) break; // EOF      

      total = n;
      YIELD_STR();
      Fiber_make_runnable(rb_fiber_current(), Qnil);
      switchpoint_result = Thread_switch_fiber(rb_thread_current());
      if (TEST_EXCEPTION(switchpoint_result)) {
        goto error;
      }
    }
  }

  RB_GC_GUARD(str);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return io;
error:
  return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
}

VALUE LibevAgent_write(VALUE self, VALUE io, VALUE str) {
  struct LibevAgent_t *agent;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;

  char *buf = StringValuePtr(str);
  long len = RSTRING_LEN(str);
  long left = len;

  VALUE underlying_io = rb_iv_get(io, "@io");
  if (underlying_io != Qnil) io = underlying_io;
  GetLibevAgent(self, agent);
  io = rb_io_get_write_io(io);
  GetOpenFile(io, fptr);
  watcher.fiber = Qnil;

  while (left > 0) {
    ssize_t n = write(fptr->fd, buf, left);
    if (n < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_io_wait(agent, &watcher, fptr, EV_WRITE);
      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      switchpoint_result = libev_snooze();
      if (TEST_EXCEPTION(switchpoint_result)) goto error;

      buf += n;
      left -= n;
    }
  }

  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);

  return INT2NUM(len);
error:
  return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
}

///////////////////////////////////////////////////////////////////////////

VALUE LibevAgent_accept(VALUE self, VALUE sock) {
  struct LibevAgent_t *agent;
  struct libev_io watcher;
  rb_io_t *fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;
  VALUE underlying_sock = rb_iv_get(sock, "@io");
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetLibevAgent(self, agent);
  GetOpenFile(sock, fptr);
  rb_io_set_nonblock(fptr);
  watcher.fiber = Qnil;
  while (1) {
    fd = accept(fptr->fd, &addr, &len);
    if (fd < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_io_wait(agent, &watcher, fptr, EV_READ);
      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      VALUE socket;
      rb_io_t *fp;
      switchpoint_result = libev_snooze();
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
      rb_io_set_nonblock(fp);
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
  return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
}

VALUE LibevAgent_accept_loop(VALUE self, VALUE sock) {
  struct LibevAgent_t *agent;
  struct libev_io watcher;
  rb_io_t *fptr;
  int fd;
  struct sockaddr addr;
  socklen_t len = (socklen_t)sizeof addr;
  VALUE switchpoint_result = Qnil;
  VALUE socket = Qnil;
  VALUE underlying_sock = rb_iv_get(sock, "@io");
  if (underlying_sock != Qnil) sock = underlying_sock;

  GetLibevAgent(self, agent);
  GetOpenFile(sock, fptr);
  rb_io_set_nonblock(fptr);
  watcher.fiber = Qnil;

  while (1) {
    fd = accept(fptr->fd, &addr, &len);
    if (fd < 0) {
      int e = errno;
      if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

      switchpoint_result = libev_io_wait(agent, &watcher, fptr, EV_READ);
      if (TEST_EXCEPTION(switchpoint_result)) goto error;
    }
    else {
      rb_io_t *fp;
      switchpoint_result = libev_snooze();
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
      rb_io_set_nonblock(fp);
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
  return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
}

// VALUE LibevAgent_connect(VALUE self, VALUE sock, VALUE host, VALUE port) {
//   struct LibevAgent_t *agent;
//   struct libev_io watcher;
//   rb_io_t *fptr;
//   struct sockaddr_in addr;
//   char *host_buf = StringValueCStr(host);
//   VALUE switchpoint_result = Qnil;
//   VALUE underlying_sock = rb_iv_get(sock, "@io");
//   if (underlying_sock != Qnil) sock = underlying_sock;

//   GetLibevAgent(self, agent);
//   GetOpenFile(sock, fptr);
//   rb_io_set_nonblock(fptr);
//   watcher.fiber = Qnil;

//   addr.sin_family = AF_INET; 
//   addr.sin_addr.s_addr = inet_addr(host_buf);
//   addr.sin_port = htons(NUM2INT(port));   

//   while (1) {
//     int result = connect(fptr->fd, &addr, sizeof(addr));
//     if (result < 0) {
//       int e = errno;
//       if ((e != EWOULDBLOCK && e != EAGAIN)) rb_syserr_fail(e, strerror(e));

//       switchpoint_result = libev_io_wait(agent, &watcher, fptr, EV_WRITE);
//       if (TEST_EXCEPTION(switchpoint_result)) goto error;
//     }
//     else {
//       switchpoint_result = libev_snooze();
//       if (TEST_EXCEPTION(switchpoint_result)) goto error;

//       return sock;
//     }
//   }
//   RB_GC_GUARD(switchpoint_result);
//   return Qnil;
// error:
//   return rb_funcall(rb_mKernel, ID_raise, 1, switchpoint_result);
// }

VALUE LibevAgent_wait_io(VALUE self, VALUE io, VALUE write) {
  struct LibevAgent_t *agent;
  struct libev_io watcher;
  rb_io_t *fptr;
  VALUE switchpoint_result = Qnil;
  int events = RTEST(write) ? EV_WRITE : EV_READ;

  VALUE underlying_io = rb_iv_get(io, "@io");
  GetLibevAgent(self, agent);
  if (underlying_io != Qnil) io = underlying_io;
  GetOpenFile(io, fptr);
  
  watcher.fiber = rb_fiber_current();
  ev_io_init(&watcher.io, LibevAgent_io_callback, fptr->fd, events);
  ev_io_start(agent->ev_loop, &watcher.io);
  switchpoint_result = libev_await(agent);
  ev_io_stop(agent->ev_loop, &watcher.io);
  
  TEST_RESUME_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

struct libev_timer {
  struct ev_timer timer;
  VALUE fiber;
};

void LibevAgent_timer_callback(EV_P_ ev_timer *w, int revents)
{
  struct libev_timer *watcher = (struct libev_timer *)w;
  Fiber_make_runnable(watcher->fiber, Qnil);
}

VALUE LibevAgent_sleep(VALUE self, VALUE duration) {
  struct LibevAgent_t *agent;
  struct libev_timer watcher;
  VALUE switchpoint_result = Qnil;

  GetLibevAgent(self, agent);
  watcher.fiber = rb_fiber_current();
  ev_timer_init(&watcher.timer, LibevAgent_timer_callback, NUM2DBL(duration), 0.);
  ev_timer_start(agent->ev_loop, &watcher.timer);

  switchpoint_result = libev_await(agent);
  ev_timer_stop(agent->ev_loop, &watcher.timer);

  TEST_RESUME_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

struct libev_child {
  struct ev_child child;
  VALUE fiber;
};

void LibevAgent_child_callback(EV_P_ ev_child *w, int revents)
{
  struct libev_child *watcher = (struct libev_child *)w;
  int exit_status = w->rstatus >> 8; // weird, why should we do this?
  VALUE status;

  status = rb_ary_new_from_args(2, INT2NUM(w->rpid), INT2NUM(exit_status));
  Fiber_make_runnable(watcher->fiber, status);
}

VALUE LibevAgent_waitpid(VALUE self, VALUE pid) {
  struct LibevAgent_t *agent;
  struct libev_child watcher;
  VALUE switchpoint_result = Qnil;
  GetLibevAgent(self, agent);

  watcher.fiber = rb_fiber_current();
  ev_child_init(&watcher.child, LibevAgent_child_callback, NUM2INT(pid), 0);
  ev_child_start(agent->ev_loop, &watcher.child);
  
  switchpoint_result = libev_await(agent);
  ev_child_stop(agent->ev_loop, &watcher.child);

  TEST_RESUME_EXCEPTION(switchpoint_result);
  RB_GC_GUARD(watcher.fiber);
  RB_GC_GUARD(switchpoint_result);
  return switchpoint_result;
}

struct ev_loop *LibevAgent_ev_loop(VALUE self) {
  struct LibevAgent_t *agent;
  GetLibevAgent(self, agent);
  return agent->ev_loop;
}

void Init_LibevAgent() {
  rb_require("socket");
  cTCPSocket = rb_const_get(rb_cObject, rb_intern("TCPSocket"));

  cLibevAgent = rb_define_class_under(mPolyphony, "LibevAgent", rb_cData);
  rb_define_alloc_func(cLibevAgent, LibevAgent_allocate);

  rb_define_method(cLibevAgent, "initialize", LibevAgent_initialize, 0);
  rb_define_method(cLibevAgent, "finalize", LibevAgent_finalize, 0);
  rb_define_method(cLibevAgent, "post_fork", LibevAgent_post_fork, 0);
  rb_define_method(cLibevAgent, "pending_count", LibevAgent_pending_count, 0);

  rb_define_method(cLibevAgent, "ref", LibevAgent_ref, 0);
  rb_define_method(cLibevAgent, "unref", LibevAgent_unref, 0);

  rb_define_method(cLibevAgent, "poll", LibevAgent_poll, 3);
  rb_define_method(cLibevAgent, "break", LibevAgent_break, 0);

  rb_define_method(cLibevAgent, "read", LibevAgent_read, 4);
  rb_define_method(cLibevAgent, "read_loop", LibevAgent_read_loop, 1);
  rb_define_method(cLibevAgent, "write", LibevAgent_write, 2);
  rb_define_method(cLibevAgent, "accept", LibevAgent_accept, 1);
  rb_define_method(cLibevAgent, "accept_loop", LibevAgent_accept_loop, 1);
  // rb_define_method(cLibevAgent, "connect", LibevAgent_accept, 3);
  rb_define_method(cLibevAgent, "wait_io", LibevAgent_wait_io, 2);
  rb_define_method(cLibevAgent, "sleep", LibevAgent_sleep, 1);
  rb_define_method(cLibevAgent, "waitpid", LibevAgent_waitpid, 1);
}
