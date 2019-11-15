#include "gyro.h"

static VALUE Gyro_run(VALUE self);
static VALUE Gyro_break(VALUE self);
static VALUE Gyro_start(VALUE self);
static VALUE Gyro_restart(VALUE self);

static VALUE Gyro_ref(VALUE self);
static VALUE Gyro_unref(VALUE self);

static VALUE Gyro_defer(VALUE self);
static VALUE Gyro_post_fork(VALUE self);

static VALUE Gyro_suspend(VALUE self);

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self);
static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self);

void Gyro_defer_callback(struct ev_loop *ev_loop, struct ev_idle *watcher, int revents);

VALUE mGyro;

VALUE Gyro_reactor_fiber;
VALUE Gyro_root_fiber;
VALUE Gyro_post_run_fiber;

static VALUE watcher_refs;
static VALUE deferred_items;

static struct ev_idle idle_watcher;
static int deferred_active;

ID ID_call;
ID ID_caller;
ID ID_clear;
ID ID_each;
ID ID_inspect;
ID ID_raise;
ID ID_read_watcher;
ID ID_scheduled_value;
ID ID_transfer;
ID ID_write_watcher;
ID ID_R;
ID ID_W;
ID ID_RW;

void Init_Gyro() {
  mGyro = rb_define_module("Gyro");

  rb_define_singleton_method(mGyro, "break", Gyro_break, 0);
  rb_define_singleton_method(mGyro, "defer", Gyro_defer, 0);
  rb_define_singleton_method(mGyro, "post_fork", Gyro_post_fork, 0);
  rb_define_singleton_method(mGyro, "ref", Gyro_ref, 0);
  rb_define_singleton_method(mGyro, "start", Gyro_start, 0);
  rb_define_singleton_method(mGyro, "restart", Gyro_restart, 0);
  rb_define_singleton_method(mGyro, "snooze", Gyro_snooze, 0);
  rb_define_singleton_method(mGyro, "unref", Gyro_unref, 0);

  rb_define_global_function("defer", Gyro_defer, 0);
  rb_define_global_function("snooze", Gyro_snooze, 0);
  rb_define_global_function("suspend", Gyro_suspend, 0);

  VALUE cFiber = rb_const_get(rb_cObject, rb_intern("Fiber"));
  rb_define_method(cFiber, "safe_transfer", Fiber_safe_transfer, -1);
  rb_define_method(cFiber, "schedule", Fiber_schedule, -1);

  ID_call             = rb_intern("call");
  ID_caller           = rb_intern("caller");
  ID_clear            = rb_intern("clear");
  ID_each             = rb_intern("each");
  ID_inspect          = rb_intern("inspect");
  ID_raise            = rb_intern("raise");
  ID_read_watcher     = rb_intern("read_watcher");
  ID_scheduled_value  = rb_intern("@scheduled_value");
  ID_transfer         = rb_intern("transfer");
  ID_write_watcher    = rb_intern("write_watcher");
  ID_R                = rb_intern("r");
  ID_W                = rb_intern("w");
  ID_RW               = rb_intern("rw");

  Gyro_root_fiber = rb_fiber_current();
  Gyro_reactor_fiber = rb_fiber_new(Gyro_run, Qnil);
  rb_gv_set("__reactor_fiber__", Gyro_reactor_fiber);
  

  watcher_refs = rb_hash_new();
  rb_global_variable(&watcher_refs);

  deferred_items = rb_ary_new();
  rb_global_variable(&deferred_items);

  ev_idle_init(&idle_watcher, Gyro_defer_callback);
  deferred_active = 0;
}

static VALUE Gyro_run(VALUE self) {
  Gyro_post_run_fiber = Qnil;
  ev_run(EV_DEFAULT, 0);
  rb_gv_set("__reactor_fiber__", Qnil);

  if (Gyro_post_run_fiber != Qnil) {
    rb_funcall(Gyro_post_run_fiber, ID_transfer, 0);
  }

  return Qnil;
}

static VALUE Gyro_break(VALUE self) {
  // make sure reactor fiber is alive
  if (!RTEST(rb_fiber_alive_p(Gyro_reactor_fiber))) {
    return Qnil;
  }

  ev_break(EV_DEFAULT, EVBREAK_ALL);
  return YIELD_TO_REACTOR();
}

static VALUE Gyro_start(VALUE self) {
  rb_ary_clear(deferred_items);
  Gyro_post_run_fiber = Qnil;
  Gyro_reactor_fiber = rb_fiber_new(Gyro_run, Qnil);
  rb_gv_set("__reactor_fiber__", Gyro_reactor_fiber);
  return Qnil;
}

static VALUE Gyro_restart(VALUE self) {
  rb_ary_clear(deferred_items);
  Gyro_post_run_fiber = rb_fiber_current();
  Gyro_break(self);
  // control will be transferred back to here after reactor loop is done
  Gyro_start(self);

  return Qnil;
}

static VALUE Gyro_ref(VALUE self) {
  ev_ref(EV_DEFAULT);
  return Qnil;
}

static VALUE Gyro_unref(VALUE self) {
  ev_unref(EV_DEFAULT);
  return Qnil;
}

void Gyro_add_watcher_ref(VALUE obj) {
  rb_hash_aset(watcher_refs, rb_obj_id(obj), obj);
}

void Gyro_del_watcher_ref(VALUE obj) {
  rb_hash_delete(watcher_refs, rb_obj_id(obj));
}

static VALUE Gyro_defer(VALUE self) {
  VALUE proc = rb_block_proc();
  if (RTEST(proc)) {
    rb_ary_push(deferred_items, proc);
    if (!deferred_active) {
      deferred_active = 1;
      ev_idle_start(EV_DEFAULT, &idle_watcher);
    }
  }
  return Qnil;
}

VALUE Gyro_snooze(VALUE self) {
  VALUE ret;
  VALUE fiber = rb_fiber_current();

  rb_ary_push(deferred_items, fiber);
  if (!deferred_active) {
    deferred_active = 1;
    ev_idle_start(EV_DEFAULT, &idle_watcher);
  }

  ret = YIELD_TO_REACTOR();
  
  // fiber is resumed, check if resumed value is an exception
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    rb_ary_delete(deferred_items, fiber);
    return rb_funcall(ret, ID_raise, 1, ret);
  }
  else {
    return ret;
  }
}

static VALUE Gyro_post_fork(VALUE self) {
  ev_loop_fork(EV_DEFAULT);
  
  Gyro_reactor_fiber = rb_fiber_new(Gyro_run, Qnil);
  rb_gv_set("__reactor_fiber__", Gyro_reactor_fiber);
  Gyro_root_fiber = rb_fiber_current();

  return Qnil;
}

VALUE run_deferred(VALUE proc) {
  if (rb_obj_is_proc(proc)) {
    rb_funcall(proc, ID_call, 1, Qtrue);
  }
  else {
    SCHEDULE_FIBER(proc, 1, rb_ivar_get(proc, ID_scheduled_value));
  }
  return Qnil;
}

void Gyro_defer_callback(struct ev_loop *ev_loop, struct ev_idle *watcher, int revents) {
  VALUE scheduled_items = deferred_items;
  deferred_items = rb_ary_new();

  long len = RARRAY_LEN(scheduled_items);
  for (long i = 0; i < len; i++) {
    run_deferred(RARRAY_AREF(scheduled_items, i));
  }

  // if no next tick items were added during callback, stop the idle watcher
  if (rb_array_len(deferred_items) == 0) {
    deferred_active = 0;
    ev_idle_stop(EV_DEFAULT, &idle_watcher);
  }
}

static VALUE Gyro_suspend(VALUE self) {
  if (!RTEST(rb_fiber_alive_p(Gyro_reactor_fiber))) {
    return Qnil;
  }

  VALUE ret = YIELD_TO_REACTOR();

  // fiber is resumed, check if resumed value is an exception
  return RTEST(rb_obj_is_kind_of(ret, rb_eException)) ? 
    rb_funcall(ret, ID_raise, 1, ret) : ret;
}

static VALUE Gyro_schedule_fiber(VALUE self, VALUE fiber, VALUE value) {
  rb_ivar_set(fiber, ID_scheduled_value, value);

  rb_ary_push(deferred_items, fiber);
  if (!deferred_active) {
    deferred_active = 1;
    ev_idle_start(EV_DEFAULT, &idle_watcher);
  }

  return Qnil;
}

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];
  VALUE ret = rb_funcall(self, ID_transfer, 1, arg);

  // fiber is resumed, check if resumed value is an exception
  return RTEST(rb_obj_is_kind_of(ret, rb_eException)) ? 
    rb_funcall(ret, ID_raise, 1, ret) : ret;
}

static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];

  Gyro_schedule_fiber(Qnil, self, arg);
  return self;
}