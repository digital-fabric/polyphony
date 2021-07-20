#ifndef POLYPHONY_H
#define POLYPHONY_H

#include <execinfo.h>

#include "ruby.h"
#include "runqueue_ring_buffer.h"
#include "backend_common.h"

// debugging
#define OBJ_ID(obj) (NUM2LONG(rb_funcall(obj, rb_intern("object_id"), 0)))
#define INSPECT(str, obj) { printf(str); VALUE s = rb_funcall(obj, rb_intern("inspect"), 0); printf(": %s\n", StringValueCStr(s)); }
#define TRACE_CALLER() { VALUE c = rb_funcall(rb_mKernel, rb_intern("caller"), 0); INSPECT("caller: ", c); }
#define TRACE_C_STACK() { \
  void *entries[10]; \
  size_t size = backtrace(entries, 10); \
  char **strings = backtrace_symbols(entries, size); \
  for (unsigned long i = 0; i < size; i++) printf("%s\n", strings[i]); \
  free(strings); \
}

// exceptions
#define TEST_EXCEPTION(ret) (rb_obj_is_kind_of(ret, rb_eException) == Qtrue)
#define RAISE_EXCEPTION(e) rb_funcall(e, ID_invoke, 0);
#define RAISE_IF_EXCEPTION(ret) if (rb_obj_is_kind_of(ret, rb_eException) == Qtrue) { RAISE_EXCEPTION(ret); }
#define RAISE_IF_NOT_NIL(ret) if (ret != Qnil) { RAISE_EXCEPTION(ret); }

// Fiber#transfer
#define FIBER_TRANSFER(fiber, value) rb_funcall(fiber, ID_transfer, 1, value)

#define BACKEND() (rb_ivar_get(rb_thread_current(), ID_ivar_backend))

extern VALUE mPolyphony;
extern VALUE cQueue;
extern VALUE cEvent;
extern VALUE cTimeoutException;

extern ID ID_call;
extern ID ID_caller;
extern ID ID_clear;
extern ID ID_each;
extern ID ID_inspect;
extern ID ID_invoke;
extern ID ID_ivar_backend;
extern ID ID_ivar_blocking_mode;
extern ID ID_ivar_io;
extern ID ID_ivar_runnable;
extern ID ID_ivar_running;
extern ID ID_ivar_thread;
extern ID ID_new;
extern ID ID_raise;
extern ID ID_signal;
extern ID ID_size;
extern ID ID_switch_fiber;
extern ID ID_transfer;

extern VALUE SYM_fiber_create;
extern VALUE SYM_fiber_event_poll_enter;
extern VALUE SYM_fiber_event_poll_leave;
extern VALUE SYM_fiber_run;
extern VALUE SYM_fiber_schedule;
extern VALUE SYM_fiber_switchpoint;
extern VALUE SYM_fiber_terminate;

VALUE Fiber_auto_watcher(VALUE self);
void Fiber_make_runnable(VALUE fiber, VALUE value);

VALUE Queue_push(VALUE self, VALUE value);
VALUE Queue_unshift(VALUE self, VALUE value);
VALUE Queue_shift(VALUE self);
VALUE Queue_shift_all(VALUE self);

void Runqueue_push(VALUE self, VALUE fiber, VALUE value, int reschedule);
void Runqueue_unshift(VALUE self, VALUE fiber, VALUE value, int reschedule);
runqueue_entry Runqueue_shift(VALUE self);
void Runqueue_delete(VALUE self, VALUE fiber);
int Runqueue_index_of(VALUE self, VALUE fiber);
void Runqueue_clear(VALUE self);
long Runqueue_len(VALUE self);
int Runqueue_empty_p(VALUE self);
int Runqueue_should_poll_nonblocking(VALUE self);

#ifdef POLYPHONY_BACKEND_LIBEV
#define Backend_recv_loop Backend_read_loop
#define Backend_recv_feed_loop Backend_feed_loop
#endif

// Backend public interface

VALUE Backend_accept(VALUE self, VALUE server_socket, VALUE socket_class);
VALUE Backend_accept_loop(VALUE self, VALUE server_socket, VALUE socket_class);
VALUE Backend_connect(VALUE self, VALUE io, VALUE addr, VALUE port);
VALUE Backend_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method);
VALUE Backend_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof, VALUE pos);
VALUE Backend_read_loop(VALUE self, VALUE io, VALUE maxlen);
VALUE Backend_recv(VALUE self, VALUE io, VALUE str, VALUE length, VALUE pos);
VALUE Backend_recv_loop(VALUE self, VALUE io, VALUE maxlen);
VALUE Backend_recv_feed_loop(VALUE self, VALUE io, VALUE receiver, VALUE method);
VALUE Backend_send(VALUE self, VALUE io, VALUE msg, VALUE flags);
VALUE Backend_sendv(VALUE self, VALUE io, VALUE ary, VALUE flags);
VALUE Backend_sleep(VALUE self, VALUE duration);
VALUE Backend_splice(VALUE self, VALUE src, VALUE dest, VALUE maxlen);
VALUE Backend_splice_to_eof(VALUE self, VALUE src, VALUE dest, VALUE chunksize);
VALUE Backend_timeout(int argc,VALUE *argv, VALUE self);
VALUE Backend_timer_loop(VALUE self, VALUE interval);
VALUE Backend_wait_event(VALUE self, VALUE raise);
VALUE Backend_wait_io(VALUE self, VALUE io, VALUE write);
VALUE Backend_waitpid(VALUE self, VALUE pid);
VALUE Backend_write_m(int argc, VALUE *argv, VALUE self);

VALUE Backend_poll(VALUE self, VALUE blocking);
VALUE Backend_wait_event(VALUE self, VALUE raise_on_exception);
VALUE Backend_wakeup(VALUE self);
VALUE Backend_run_idle_tasks(VALUE self);
VALUE Backend_switch_fiber(VALUE self);
void Backend_schedule_fiber(VALUE thread, VALUE self, VALUE fiber, VALUE value, int prioritize);
void Backend_unschedule_fiber(VALUE self, VALUE fiber);

VALUE Thread_schedule_fiber(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_schedule_fiber_with_priority(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_switch_fiber(VALUE thread);

VALUE Polyphony_snooze(VALUE self);

#endif /* POLYPHONY_H */