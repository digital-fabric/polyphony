#ifndef POLYPHONY_H
#define POLYPHONY_H

#include <execinfo.h>

#include "ruby.h"
#include "backend.h"
#include "runqueue_ring_buffer.h"

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

// tracing
#define TRACE(...)  rb_funcall(rb_cObject, ID_fiber_trace, __VA_ARGS__)
#define COND_TRACE(...) if (__tracing_enabled__) { TRACE(__VA_ARGS__); }

#define TEST_EXCEPTION(ret) (RTEST(rb_obj_is_kind_of(ret, rb_eException)))

#define RAISE_EXCEPTION(e) rb_funcall(e, ID_invoke, 0);
#define RAISE_IF_EXCEPTION(ret) if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) { RAISE_EXCEPTION(ret); }
#define RAISE_IF_NOT_NIL(ret) if (ret != Qnil) { RAISE_EXCEPTION(ret); }

extern backend_interface_t backend_interface;
#define __BACKEND__ (backend_interface)

extern VALUE mPolyphony;
extern VALUE cQueue;
extern VALUE cEvent;
extern VALUE cRunqueue;

extern ID ID_call;
extern ID ID_caller;
extern ID ID_clear;
extern ID ID_each;
extern ID ID_fiber_trace;
extern ID ID_inspect;
extern ID ID_invoke;
extern ID ID_ivar_backend;
extern ID ID_ivar_running;
extern ID ID_ivar_thread;
extern ID ID_new;
extern ID ID_raise;
extern ID ID_ivar_runnable;
extern ID ID_signal;
extern ID ID_size;
extern ID ID_switch_fiber;
extern ID ID_transfer;

extern VALUE SYM_fiber_create;
extern VALUE SYM_backend_poll_enter;
extern VALUE SYM_backend_poll_leave;
extern VALUE SYM_fiber_run;
extern VALUE SYM_fiber_schedule;
extern VALUE SYM_fiber_switchpoint;
extern VALUE SYM_fiber_terminate;

extern int __tracing_enabled__;

enum {
  FIBER_STATE_NOT_SCHEDULED = 0,
  FIBER_STATE_WAITING       = 1,
  FIBER_STATE_SCHEDULED     = 2
};

VALUE Fiber_auto_watcher(VALUE self);
void Fiber_make_runnable(VALUE fiber, VALUE value);

VALUE Queue_push(VALUE self, VALUE value);
VALUE Queue_unshift(VALUE self, VALUE value);
VALUE Queue_shift(VALUE self);
VALUE Queue_shift_all(VALUE self);
VALUE Queue_shift_no_wait(VALUE self);
VALUE Queue_clear(VALUE self);
VALUE Queue_delete(VALUE self, VALUE value);
long Queue_len(VALUE self);
void Queue_trace(VALUE self);


void Runqueue_push(VALUE self, VALUE fiber, VALUE value, int reschedule);
void Runqueue_unshift(VALUE self, VALUE fiber, VALUE value, int reschedule);
runqueue_entry Runqueue_shift(VALUE self);
void Runqueue_delete(VALUE self, VALUE fiber);
void Runqueue_clear(VALUE self);
long Runqueue_len(VALUE self);
int Runqueue_empty_p(VALUE self);

VALUE Thread_schedule_fiber(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_schedule_fiber_with_priority(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_switch_fiber(VALUE thread);

#endif /* POLYPHONY_H */