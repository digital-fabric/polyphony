#include "gyro.h"

static VALUE Gyro_break_set(VALUE self);
static VALUE Gyro_break_get(VALUE self);

static VALUE Gyro_ref(VALUE self);
static VALUE Gyro_unref(VALUE self);

static VALUE Gyro_run(VALUE self);
static VALUE Gyro_reset(VALUE self);
static VALUE Gyro_post_fork(VALUE self);
static VALUE Gyro_suspend(VALUE self);

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self);
static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self);
static VALUE Fiber_state(VALUE self);

static void Gyro_clear_scheduled_fibers();

VALUE mGyro;

int break_flag = 0;
int ref_count = 0;

static VALUE scheduled_head;
static VALUE scheduled_tail;
static VALUE scheduled_fibers_queue;

ID ID_call;
ID ID_caller;
ID ID_clear;
ID ID_each;
ID ID_inspect;
ID ID_new;
ID ID_raise;
ID ID_running;
ID ID_scheduled;
ID ID_scheduled_next;
ID ID_scheduled_value;
ID ID_size;
ID ID_signal_bang;
ID ID_switch_fiber;
ID ID_transfer;
ID ID_R;
ID ID_W;
ID ID_RW;

ID ID_empty;
ID ID_pop;
ID ID_push;

VALUE SYM_DEAD;
VALUE SYM_RUNNING;
VALUE SYM_SCHEDULED;
VALUE SYM_SUSPENDED;

void Init_Gyro() {
  mGyro = rb_define_module("Gyro");

  rb_define_singleton_method(mGyro, "ref", Gyro_ref, 0);
  rb_define_singleton_method(mGyro, "unref", Gyro_unref, 0);

  rb_define_singleton_method(mGyro, "run", Gyro_run, 0);
  rb_define_singleton_method(mGyro, "reset!", Gyro_reset, 0);
  rb_define_singleton_method(mGyro, "post_fork", Gyro_post_fork, 0);
  rb_define_singleton_method(mGyro, "snooze", Gyro_snooze, 0);

  rb_define_singleton_method(mGyro, "break!", Gyro_break_set, 0);
  rb_define_singleton_method(mGyro, "break?", Gyro_break_get, 0);

  rb_define_global_function("snooze", Gyro_snooze, 0);
  rb_define_global_function("suspend", Gyro_suspend, 0);

  VALUE cFiber = rb_const_get(rb_cObject, rb_intern("Fiber"));
  rb_define_method(cFiber, "safe_transfer", Fiber_safe_transfer, -1);
  rb_define_method(cFiber, "schedule", Fiber_schedule, -1);
  rb_define_method(cFiber, "state", Fiber_state, 0);

  ID_call             = rb_intern("call");
  ID_caller           = rb_intern("caller");
  ID_clear            = rb_intern("clear");
  ID_each             = rb_intern("each");
  ID_inspect          = rb_intern("inspect");
  ID_new              = rb_intern("new");
  ID_raise            = rb_intern("raise");
  ID_running          = rb_intern("@running");
  ID_scheduled        = rb_intern("scheduled");
  ID_scheduled_next   = rb_intern("scheduled_next");
  ID_scheduled_value  = rb_intern("scheduled_value");
  ID_size             = rb_intern("size");
  ID_signal_bang      = rb_intern("signal!");
  ID_switch_fiber     = rb_intern("switch_fiber");
  ID_transfer         = rb_intern("transfer");
  ID_R                = rb_intern("r");
  ID_W                = rb_intern("w");
  ID_RW               = rb_intern("rw");

  ID_empty            = rb_intern("empty?");
  ID_pop              = rb_intern("pop");
  ID_push             = rb_intern("push");

  SYM_DEAD = ID2SYM(rb_intern("dead"));
  SYM_RUNNING = ID2SYM(rb_intern("running"));
  SYM_SCHEDULED = ID2SYM(rb_intern("scheduled"));
  SYM_SUSPENDED = ID2SYM(rb_intern("suspended"));
  rb_global_variable(&SYM_DEAD);
  rb_global_variable(&SYM_RUNNING);
  rb_global_variable(&SYM_SCHEDULED);
  rb_global_variable(&SYM_SUSPENDED);

  scheduled_head = Qnil;
  scheduled_tail = Qnil;
  rb_global_variable(&scheduled_head);

  VALUE cQueue = rb_const_get(rb_cObject, rb_intern("Queue"));
  scheduled_fibers_queue = rb_funcall(cQueue, rb_intern("new"), 0);
  rb_global_variable(&scheduled_fibers_queue);
}

static VALUE Gyro_ref(VALUE self) {
  Gyro_ref_count_incr();
  return Qnil;
}

static VALUE Gyro_unref(VALUE self) {
  Gyro_ref_count_decr();
  return Qnil;
}

static VALUE Gyro_run(VALUE self) {
  return Gyro_run_next_fiber();
}

static VALUE Gyro_reset(VALUE self) {
  break_flag = 0;
  ref_count = 0;

  Gyro_clear_scheduled_fibers();
  return Qnil;
}

static VALUE Gyro_break_set(VALUE self) {
  break_flag = 1;
  ev_break(EV_DEFAULT, EVBREAK_ALL);
  return Qnil;
}

static VALUE Gyro_break_get(VALUE self) {
  return (break_flag == 0) ? Qfalse : Qtrue;
}

VALUE Gyro_snooze(VALUE self) {
  VALUE fiber = rb_fiber_current();
  Gyro_schedule_fiber(fiber, Qnil);

  VALUE ret = Gyro_run_next_fiber();
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException)))
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  else
    return ret;
}

static VALUE Gyro_post_fork(VALUE self) {
  ev_loop_fork(EV_DEFAULT);
  break_flag = 0;
  ref_count = 0;
  
  Gyro_clear_scheduled_fibers();

  return Qnil;
}

static VALUE Gyro_suspend(VALUE self) {
  rb_ivar_set(self, ID_scheduled_value, Qnil);
  VALUE ret = Gyro_run_next_fiber();
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  }
  else {
    return ret;
  }
}

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];
  VALUE ret = rb_funcall(self, ID_transfer, 1, arg);

  // fiber is resumed, check if resumed value is an exception
  return RTEST(rb_obj_is_kind_of(ret, rb_eException)) ? 
    rb_funcall(rb_mKernel, ID_raise, 1, ret) : ret;
}

static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self) {
  VALUE value = (argc == 0) ? Qnil : argv[0];
  Gyro_schedule_fiber(self, value);
  return self;
}

static VALUE Fiber_state(VALUE self) {
  if (!rb_fiber_alive_p(self) || (rb_ivar_get(self, ID_running) == Qfalse))
    return SYM_DEAD;
  if (rb_fiber_current() == self) return SYM_RUNNING;
  if (rb_ivar_get(self, ID_scheduled) != Qnil) return SYM_SCHEDULED;
  
  return SYM_SUSPENDED;
}

inline VALUE Gyro_await() {
  VALUE thread = rb_thread_current();
  Thread_ref(thread);
  VALUE ret = Thread_switch_fiber(thread);
  Thread_unref(thread);
  return ret;
}

VALUE Gyro_run_next_fiber() {
  return Thread_switch_fiber(rb_thread_current());
  // while (1) {
  //   if (break_flag != 0) {
  //     return Qnil;
  //   }
  //   if ((rb_funcall(scheduled_fibers_queue, ID_empty, 0) == Qfalse) || (ref_count == 0)) {
  //     break;
  //   }
  //   // if ((scheduled_head != Qnil) || (ref_count == 0)) {
  //   //   break;
  //   // }
  //   ev_run(EV_DEFAULT, EVRUN_ONCE);
  // }

  // VALUE next_fiber = rb_funcall(scheduled_fibers_queue, ID_pop, 1, Qtrue);
  // if (next_fiber == Qnil) {
  //   return Qnil;
  // }

  // // return if no fiber is scheduled
  // // if (scheduled_head == Qnil) {
  // //   return Qnil;
  // // }

  // // update scheduled linked list refs
  // // VALUE next_fiber = scheduled_head;
  // // VALUE next_next_fiber = rb_ivar_get(next_fiber, ID_scheduled_next);
  // // rb_ivar_set(next_fiber, ID_scheduled_next, Qnil);
  // // scheduled_head = next_next_fiber;
  // // if (scheduled_head == Qnil) {
  // //   scheduled_tail = Qnil;
  // // }

  // if (rb_fiber_alive_p(next_fiber) != Qtrue) {
  //   return Qnil;
  // }

  // // run next fiber
  // VALUE value = rb_ivar_get(next_fiber, ID_scheduled_value);
  // // rb_ivar_set(next_fiber, ID_scheduled_value, Qnil);
  // rb_ivar_set(next_fiber, ID_scheduled, Qnil);
  // return rb_funcall(next_fiber, ID_transfer, 1, value);
}

void Gyro_schedule_fiber(VALUE fiber, VALUE value) {
  rb_ivar_set(fiber, ID_scheduled_value, value);
  // if fiber is already scheduled, we just set the scheduled value, then return
  if (rb_ivar_get(fiber, ID_scheduled) != Qnil)
    return;

  rb_ivar_set(fiber, ID_scheduled, Qtrue);

  // put fiber on scheduled list
  // if (scheduled_head != Qnil) {
  //   VALUE last = scheduled_tail;
  //   rb_ivar_set(last, ID_scheduled_next, fiber);
  //   scheduled_tail = fiber;
  // }
  // else {
  //   scheduled_tail = scheduled_head = fiber;
  // }
  Thread_schedule_fiber(rb_thread_current(), fiber);
  // rb_funcall(scheduled_fibers_queue, ID_push, 1, fiber);
}

int Gyro_ref_count() {
  return ref_count;
}

void Gyro_ref_count_incr() {
  ref_count += 1;
}

void Gyro_ref_count_decr() {
  ref_count -= 1;
}

static void Gyro_clear_scheduled_fibers() {
  while (scheduled_head != Qnil) {
    VALUE fiber = scheduled_head;
    scheduled_head = rb_ivar_get(fiber, ID_scheduled_next);
    rb_ivar_set(fiber, ID_scheduled_next, Qnil);
  }
  scheduled_tail = Qnil;
}