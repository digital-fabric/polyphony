#ifndef RUBY_EV_H
#define RUBY_EV_H

#include "ruby.h"
#include "ruby/io.h"
#include "libev.h"

// debugging
#define OBJ_ID(obj) (NUM2LONG(rb_funcall(obj, rb_intern("object_id"), 0)))
#define INSPECT(obj) { VALUE s = rb_funcall(obj, rb_intern("inspect"), 0); printf("%s\n", StringValueCStr(s));}
#define FIBER_TRACE(...) if (__tracing_enabled__) { \
  rb_funcall(rb_cObject, ID_fiber_trace, __VA_ARGS__); \
}

#define TEST_EXCEPTION(ret) (RTEST(rb_obj_is_kind_of(ret, rb_eException)))

#define TEST_RESUME_EXCEPTION(ret) if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) { \
  return rb_funcall(rb_mKernel, ID_raise, 1, ret); \
}

extern VALUE mPolyphony;
extern VALUE cLibevQueue;
extern VALUE cEvent;

extern ID ID_await_no_raise;
extern ID ID_call;
extern ID ID_caller;
extern ID ID_clear;
extern ID ID_each;
extern ID ID_fiber_trace;
extern ID ID_inspect;
extern ID ID_ivar_agent;
extern ID ID_ivar_running;
extern ID ID_ivar_thread;
extern ID ID_new;
extern ID ID_raise;
extern ID ID_runnable;
extern ID ID_runnable_value;
extern ID ID_signal;
extern ID ID_size;
extern ID ID_switch_fiber;
extern ID ID_transfer;

extern VALUE SYM_fiber_create;
extern VALUE SYM_fiber_ev_loop_enter;
extern VALUE SYM_fiber_ev_loop_leave;
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

// watcher flags
enum {
  // a watcher's active field will be set to this after fork
  GYRO_WATCHER_POST_FORK = 0xFF
};

VALUE Fiber_auto_watcher(VALUE self);
void Fiber_make_runnable(VALUE fiber, VALUE value);

VALUE LibevAgent_poll(VALUE self, VALUE nowait, VALUE current_fiber, VALUE queue);
VALUE LibevAgent_break(VALUE self);
VALUE LibevAgent_pending_count(VALUE self);
VALUE LibevAgent_wait_io(VALUE self, VALUE io, VALUE write);

VALUE LibevAgent_ref(VALUE self);
VALUE LibevAgent_unref(VALUE self);
int LibevAgent_ref_count(VALUE self);
void LibevAgent_reset_ref_count(VALUE self);

VALUE Polyphony_snooze(VALUE self);

VALUE Polyphony_Queue_push(VALUE self, VALUE value);

VALUE Thread_schedule_fiber(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_switch_fiber(VALUE thread);

int io_setstrbuf(VALUE *str, long len);
void io_set_read_length(VALUE str, long n, int shrinkable);
VALUE io_enc_str(VALUE str, rb_io_t *fptr);

#endif /* RUBY_EV_H */