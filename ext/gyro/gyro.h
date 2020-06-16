#ifndef RUBY_EV_H
#define RUBY_EV_H

#include "ruby.h"
#include "ruby/io.h"
#include "libev.h"

// debugging
#define OBJ_ID(obj) (NUM2LONG(rb_funcall(obj, rb_intern("object_id"), 0)))
#define INSPECT(...) (rb_funcall(rb_cObject, rb_intern("p"), __VA_ARGS__))
#define FIBER_TRACE(...) if (__tracing_enabled__) { \
  rb_funcall(rb_cObject, ID_fiber_trace, __VA_ARGS__); \
}

#define TEST_EXCEPTION(ret) (RTEST(rb_obj_is_kind_of(ret, rb_eException)))

#define TEST_RESUME_EXCEPTION(ret) if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) { \
  return rb_funcall(rb_mKernel, ID_raise, 1, ret); \
}

typedef struct Gyro_watcher {
  int active;
  int generation;

  struct  ev_loop *ev_loop;

  VALUE   self;
  VALUE   fiber;
  VALUE   selector;
} Gyro_watcher_t;


#define GYRO_WATCHER_DECL(type) \
  struct type type; \
  int active; \
  int generation; \
  struct ev_loop *ev_loop; \
  VALUE self; \
  VALUE fiber; \
  VALUE selector;

#define GYRO_WATCHER_INITIALIZE(o, self) \
  o->active     = 0; \
  o->generation = __gyro_current_generation__; \
  o->ev_loop    = 0; \
  o->self       = self; \
  o->fiber      = Qnil; \
  o->selector   = Qnil;

#define GYRO_WATCHER_MARK(o) \
  if (o->fiber != Qnil) rb_gc_mark(o->fiber); \
  if (o->selector != Qnil) rb_gc_mark(o->selector);

#define GYRO_WATCHER_STOP_EXPAND(o) ev_ ## o ## _stop
#define GYRO_WATCHER_STOP(o) GYRO_WATCHER_STOP_EXPAND(o)

#define GYRO_WATCHER_FIELD_EXPAND(o) ev_ ## o
#define GYRO_WATCHER_FIELD(o) GYRO_WATCHER_FIELD_EXPAND(o)

#define GYRO_WATCHER_FREE(o) \
  if (o->generation < __gyro_current_generation__) return; \
  if (o->active) { \
    ev_clear_pending(o->ev_loop, &o->GYRO_WATCHER_FIELD(o)); \
    GYRO_WATCHER_STOP(o)(o->ev_loop, &o->GYRO_WATCHER_FIELD(o)); \
  } \
  xfree(o);

extern VALUE mGyro;
extern VALUE cGyro_Queue;
extern VALUE cEvent;
extern VALUE mLibev;

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
extern ID ID_signal;
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
extern int __gyro_current_generation__;

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

VALUE Gyro_switchpoint();

VALUE LibevAgent_poll(VALUE self, VALUE nowait, VALUE current_fiber, VALUE queue);
VALUE LibevAgent_break(VALUE self);

VALUE Gyro_snooze(VALUE self);

VALUE Gyro_Queue_push(VALUE self, VALUE value);

VALUE Thread_post_fork(VALUE thread);
VALUE Thread_ref(VALUE thread);
VALUE Thread_schedule_fiber(VALUE thread, VALUE fiber, VALUE value);
VALUE Thread_switch_fiber(VALUE thread);
VALUE Thread_unref(VALUE thread);

int io_setstrbuf(VALUE *str, long len);
void io_set_read_length(VALUE str, long n, int shrinkable);
VALUE io_enc_str(VALUE str, rb_io_t *fptr);

#endif /* RUBY_EV_H */