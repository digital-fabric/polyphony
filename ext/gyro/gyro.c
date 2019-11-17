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
static VALUE deferred_head;
static VALUE deferred_tail;
static VALUE deferred_eol_marker;

static struct ev_idle idle_watcher;
static int deferred_active;
static int deferred_in_callback;
static int break_flag;

ID ID_call;
ID ID_caller;
ID ID_clear;
ID ID_deferred_next;
ID ID_deferred_prev;
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
  ID_deferred_next    = rb_intern("deferred_next");
  ID_deferred_prev    = rb_intern("deferred_prev");
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

  deferred_head = Qnil;
  deferred_tail = Qnil;
  rb_global_variable(&deferred_head);

  deferred_eol_marker = rb_funcall(rb_cObject, rb_intern("new"), 0);
  rb_global_variable(&deferred_eol_marker);

  ev_idle_init(&idle_watcher, Gyro_defer_callback);
  deferred_active = 0;
  deferred_in_callback = 0;
}

static VALUE Gyro_run(VALUE self) {
  break_flag = 0;
  Gyro_post_run_fiber = Qnil;
  ev_run(EV_DEFAULT, 0);
  rb_gv_set("__reactor_fiber__", Qnil);

  if (Gyro_post_run_fiber != Qnil) {
    rb_funcall(Gyro_post_run_fiber, ID_transfer, 0);
  }

  return Qnil;
}

static VALUE Gyro_break(VALUE self) {
  break_flag = 1;
  // make sure reactor fiber is alive
  if (!RTEST(rb_fiber_alive_p(Gyro_reactor_fiber))) {
    return Qnil;
  }

  if (deferred_active) {
    deferred_active = 0;
    ev_idle_stop(EV_DEFAULT, &idle_watcher);
  }
  ev_break(EV_DEFAULT, EVBREAK_ALL);
  YIELD_TO_REACTOR();
  return Qnil;
}

static VALUE Gyro_start(VALUE self) {
  Gyro_post_run_fiber = Qnil;
  deferred_head = Qnil;
  Gyro_reactor_fiber = rb_fiber_new(Gyro_run, Qnil);
  rb_gv_set("__reactor_fiber__", Gyro_reactor_fiber);
  return Qnil;
}

static VALUE Gyro_restart(VALUE self) {
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

static void defer_add(VALUE item) {
  if (NIL_P(deferred_head)) {
    deferred_head = item;
    deferred_tail = item;
    rb_ivar_set(item, ID_deferred_next, Qnil);
    rb_ivar_set(item, ID_deferred_prev, Qnil);
  }
  else {
    rb_ivar_set(deferred_tail, ID_deferred_next, item);
    rb_ivar_set(item, ID_deferred_prev, deferred_tail);
    deferred_tail = item;
  }

  if (!deferred_active) {
    deferred_active = 1;
    ev_idle_start(EV_DEFAULT, &idle_watcher);
  }
}

static void defer_remove(VALUE item) {
  VALUE next = rb_ivar_get(item, ID_deferred_next);
  VALUE prev = rb_ivar_get(item, ID_deferred_prev);
  if (RTEST(prev)) {
    rb_ivar_set(prev, ID_deferred_next, next);
  }
  if (RTEST(next)) {
    rb_ivar_set(next, ID_deferred_prev, prev);
  }

}

static VALUE Gyro_defer(VALUE self) {
  VALUE proc = rb_block_proc();
  if (RTEST(proc)) {
    defer_add(proc);
  }
  return Qnil;
}

VALUE Gyro_snooze(VALUE self) {
  VALUE ret;
  VALUE fiber = rb_fiber_current();
  defer_add(fiber);

  ret = YIELD_TO_REACTOR();
  
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    defer_remove(fiber);
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

  deferred_head = Qnil;
  deferred_active = 0;

  return Qnil;
}

VALUE run_deferred(VALUE item) {
  if (rb_obj_is_proc(item)) {
    rb_funcall(item, ID_call, 1, Qtrue);
  }
  else {
    VALUE arg = rb_ivar_get(item, ID_scheduled_value);
    if (RTEST(rb_obj_is_kind_of(arg, rb_eException))) {
      rb_ivar_set(item, ID_scheduled_value, Qnil);
    }
    SCHEDULE_FIBER(item, 1, arg);
  }
  return Qnil;
}

void Gyro_defer_callback(struct ev_loop *ev_loop, struct ev_idle *watcher, int revents) {
  deferred_in_callback = 1;
  defer_add(deferred_eol_marker);
  rb_ivar_set(deferred_eol_marker, ID_deferred_next, Qnil);

  while (RTEST(deferred_head) && !break_flag) {
    VALUE next = rb_ivar_get(deferred_head, ID_deferred_next);
    if (deferred_head == deferred_eol_marker) {
      deferred_head = next;
      break;
    }
    run_deferred(deferred_head);
    deferred_head = next;
  }

  if (NIL_P(deferred_head)) {
    deferred_active = 0;
    ev_idle_stop(EV_DEFAULT, &idle_watcher);
  }

  deferred_in_callback = 0;
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

static VALUE Fiber_safe_transfer(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];
  VALUE ret = rb_funcall(self, ID_transfer, 1, arg);

  // fiber is resumed, check if resumed value is an exception
  return RTEST(rb_obj_is_kind_of(ret, rb_eException)) ? 
    rb_funcall(ret, ID_raise, 1, ret) : ret;
}

static VALUE Fiber_schedule(int argc, VALUE *argv, VALUE self) {
  VALUE arg = (argc == 0) ? Qnil : argv[0];
  rb_ivar_set(self, ID_scheduled_value, arg);
  if (deferred_in_callback) {
    // if a fiber is scheduled while processing deferred items, we want to avoid
    // adding the same fiber again to the list of deferred item, since this will
    // fuck up the linked list refs, and also lead to a race condition. To do
    // this, we search the deferred items linked list for the given fiber, and
    // return without readding it if found.
    VALUE next = deferred_head;
    while (RTEST(next)) {
      if (next == self) return self;
      if (next == deferred_eol_marker) break;
      next = rb_ivar_get(next, ID_deferred_next);
    }
  }
  defer_add(self);
  return self;
}