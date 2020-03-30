#include "gyro.h"

VALUE mGyro;

ID ID_call;
ID ID_caller;
ID ID_clear;
ID ID_each;
ID ID_empty;
ID ID_inspect;
ID ID_new;
ID ID_pop;
ID ID_push;
ID ID_raise;
ID ID_ivar_running;
ID ID_ivar_thread;
ID ID_runnable;
ID ID_runnable_value;
ID ID_size;
ID ID_signal;
ID ID_switch_fiber;
ID ID_transfer;
ID ID_R;
ID ID_W;
ID ID_RW;

static VALUE Gyro_break_set(VALUE self) {
  // break_flag = 1;
  ev_break(Gyro_Selector_current_thread_ev_loop(), EVBREAK_ALL);
  return Qnil;
}

// static VALUE Gyro_break_get(VALUE self) {
//   return (break_flag == 0) ? Qfalse : Qtrue;
// }

VALUE Gyro_snooze(VALUE self) {
  VALUE fiber = rb_fiber_current();
  Fiber_make_runnable(fiber, Qnil);

  VALUE ret = Thread_switch_fiber(rb_thread_current());
  TEST_RESUME_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

static VALUE Gyro_post_fork(VALUE self) {
  Thread_post_fork(rb_thread_current());
  return Qnil;
}

static VALUE Gyro_ref(VALUE self) {
  return Thread_ref(rb_thread_current());
}

static VALUE Gyro_unref(VALUE self) {
  return Thread_unref(rb_thread_current());
}

static VALUE Gyro_suspend(VALUE self) {
  VALUE ret = Thread_switch_fiber(rb_thread_current());
  
  TEST_RESUME_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

VALUE Gyro_trace(VALUE self, VALUE enabled) {
  __tracing_enabled__ = RTEST(enabled) ? 1 : 0;
  return Qnil;
}

void Init_Gyro() {
  mGyro = rb_define_module("Gyro");

  rb_define_singleton_method(mGyro, "post_fork", Gyro_post_fork, 0);
  rb_define_singleton_method(mGyro, "ref", Gyro_ref, 0);
  rb_define_singleton_method(mGyro, "unref", Gyro_unref, 0);
  rb_define_singleton_method(mGyro, "trace", Gyro_trace, 1);

  rb_define_singleton_method(mGyro, "break!", Gyro_break_set, 0);
  // rb_define_singleton_method(mGyro, "break?", Gyro_break_get, 0);

  rb_define_global_function("snooze", Gyro_snooze, 0);
  rb_define_global_function("suspend", Gyro_suspend, 0);

  ID_call           = rb_intern("call");
  ID_caller         = rb_intern("caller");
  ID_clear          = rb_intern("clear");
  ID_each           = rb_intern("each");
  ID_empty          = rb_intern("empty?");
  ID_inspect        = rb_intern("inspect");
  ID_ivar_running   = rb_intern("@running");
  ID_ivar_thread    = rb_intern("@thread");
  ID_new            = rb_intern("new");
  ID_pop            = rb_intern("pop");
  ID_push           = rb_intern("push");
  ID_raise          = rb_intern("raise");
  ID_runnable       = rb_intern("runnable");
  ID_runnable_value = rb_intern("runnable_value");
  ID_signal         = rb_intern("signal");
  ID_size           = rb_intern("size");
  ID_switch_fiber   = rb_intern("switch_fiber");
  ID_transfer       = rb_intern("transfer");

  ID_R              = rb_intern("r");
  ID_RW             = rb_intern("rw");
  ID_W              = rb_intern("w");
}