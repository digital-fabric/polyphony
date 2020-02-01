#ifndef RUBY_EV_H
#define RUBY_EV_H

#include "ruby.h"
#include "ruby/io.h"
#include "libev.h"

enum {
  FIBER_STATE_NOT_SCHEDULED = 0,
  FIBER_STATE_WAITING       = 1,
  FIBER_STATE_SCHEDULED     = 2
};

// void Gyro_add_watcher_ref(VALUE obj);
// void Gyro_del_watcher_ref(VALUE obj);
VALUE Gyro_snooze(VALUE self);

void Gyro_schedule_fiber(VALUE fiber, VALUE value);

int Gyro_ref_count();
void Gyro_ref_count_incr();
void Gyro_ref_count_decr();

VALUE Gyro_Async_await(VALUE async);

VALUE IO_read_watcher(VALUE io);
VALUE IO_write_watcher(VALUE io);
VALUE Gyro_IO_await(VALUE self);

VALUE Gyro_Selector_run(VALUE self, VALUE current_fiber);
void Gyro_Selector_run_no_wait(VALUE self, VALUE current_fiber, long runnable_count);

VALUE Gyro_Timer_await(VALUE self);

int io_setstrbuf(VALUE *str, long len);
void io_set_read_length(VALUE str, long n, int shrinkable);
VALUE io_enc_str(VALUE str, rb_io_t *fptr);

struct ev_loop *Gyro_Selector_ev_loop(VALUE selector);
ev_tstamp Gyro_Selector_now(VALUE selector);
struct ev_loop *Gyro_Selector_current_thread_ev_loop();
long Gyro_Selector_pending_count(VALUE self);

VALUE Thread_current_event_selector();
VALUE Thread_ref(VALUE thread);
VALUE Thread_unref(VALUE thread);
VALUE Thread_switch_fiber(VALUE thread);
VALUE Fiber_await();
VALUE Thread_schedule_fiber(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_post_fork(VALUE thread);


#define OBJ_ID(obj) (NUM2LONG(rb_funcall(obj, rb_intern("object_id"), 0)))
#define INSPECT(...) (rb_funcall(rb_cObject, rb_intern("p"), __VA_ARGS__))
#define FIBER_TRACE(...) if (__tracing_enabled__) { \
  rb_funcall(rb_cObject, ID_fiber_trace, __VA_ARGS__); \
}

extern VALUE mGyro;
extern VALUE cGyro_Async;
extern VALUE cGyro_IO;
extern VALUE cGyro_Queue;
extern VALUE cGyro_Selector;
extern VALUE cGyro_Timer;

extern ID ID_call;
extern ID ID_caller;
extern ID ID_clear;
extern ID ID_each;
extern ID ID_fiber_trace;
extern ID ID_inspect;
extern ID ID_ivar_running;
extern ID ID_ivar_thread;
extern ID ID_new;
extern ID ID_raise;
extern ID ID_runnable;
extern ID ID_runnable_value;
extern ID ID_signal_bang;
extern ID ID_size;
extern ID ID_switch_fiber;
extern ID ID_transfer;
extern ID ID_R;
extern ID ID_W;
extern ID ID_RW;

extern VALUE SYM_fiber_create;
extern VALUE SYM_fiber_ev_loop_enter;
extern VALUE SYM_fiber_ev_loop_leave;
extern VALUE SYM_fiber_run;
extern VALUE SYM_fiber_schedule;
extern VALUE SYM_fiber_switchpoint;
extern VALUE SYM_fiber_terminate;

extern int __tracing_enabled__;

#endif /* RUBY_EV_H */