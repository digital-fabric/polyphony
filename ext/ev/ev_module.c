#include "ev.h"

static VALUE mEV = Qnil;

static VALUE EV_run(VALUE self);
static VALUE EV_break(VALUE self);
static VALUE EV_restart(VALUE self);
static VALUE EV_rerun(VALUE self);

static VALUE EV_ref(VALUE self);
static VALUE EV_unref(VALUE self);

static VALUE EV_next_tick(VALUE self);
static VALUE EV_snooze(VALUE self);
static VALUE EV_post_fork(VALUE self);

static VALUE EV_suspend(VALUE self);
static VALUE EV_schedule_fiber(VALUE self, VALUE fiber, VALUE value);

static VALUE watcher_refs;
static VALUE next_tick_items;

static struct ev_timer next_tick_timer;
static int next_tick_active;
void EV_next_tick_callback(ev_loop *ev_loop, struct ev_timer *timer, int revents);

VALUE EV_reactor_fiber;
VALUE EV_root_fiber;

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

void Init_EV() {
  mEV = rb_define_module("EV");

  rb_define_singleton_method(mEV, "break", EV_break, 0);
  rb_define_singleton_method(mEV, "restart", EV_restart, 0);
  rb_define_singleton_method(mEV, "rerun", EV_rerun, 0);
  rb_define_singleton_method(mEV, "ref", EV_ref, 0);
  rb_define_singleton_method(mEV, "unref", EV_unref, 0);
  rb_define_singleton_method(mEV, "next_tick", EV_next_tick, 0);
  rb_define_singleton_method(mEV, "snooze", EV_snooze, 0);
  rb_define_singleton_method(mEV, "post_fork", EV_post_fork, 0);
  rb_define_singleton_method(mEV, "schedule_fiber", EV_schedule_fiber, 2);

  rb_define_global_function("suspend", EV_suspend, 0);
  rb_define_global_function("snooze", EV_snooze, 0);
  rb_define_global_function("next_tick", EV_next_tick, 0);

  ID_call                 = rb_intern("call");
  ID_caller               = rb_intern("caller");
  ID_clear                = rb_intern("clear");
  ID_each                 = rb_intern("each");
  ID_inspect              = rb_intern("inspect");
  ID_raise                = rb_intern("raise");
  ID_read_watcher         = rb_intern("read_watcher");
  ID_scheduled_value      = rb_intern("@scheduled_value");
  ID_transfer             = rb_intern("transfer");
  ID_write_watcher        = rb_intern("write_watcher");
  ID_R                    = rb_intern("r");
  ID_W                    = rb_intern("w");
  ID_RW                   = rb_intern("rw");

  EV_root_fiber = rb_fiber_current();
  EV_reactor_fiber = rb_fiber_new(EV_run, Qnil);
  rb_gv_set("__reactor_fiber__", EV_reactor_fiber);
  

  watcher_refs = rb_hash_new();
  rb_global_variable(&watcher_refs);

  next_tick_items = rb_ary_new();
  rb_global_variable(&next_tick_items);

  ev_timer_init(&next_tick_timer, EV_next_tick_callback, 0., 0.);
  next_tick_active = 0;
}

static VALUE EV_run(VALUE self) {
  ev_run(EV_DEFAULT, 0);
  rb_gv_set("__reactor_fiber__", Qnil);
  return Qnil;
}

static VALUE EV_break(VALUE self) {
  // make sure reactor fiber is alive
  if (!RTEST(rb_fiber_alive_p(EV_reactor_fiber))) {
    return Qnil;
  }

  ev_break(EV_DEFAULT, EVBREAK_ALL);
  return YIELD_TO_REACTOR();
}

static VALUE EV_restart(VALUE self) {
  EV_reactor_fiber = rb_fiber_new(EV_run, Qnil);
  rb_gv_set("__reactor_fiber__", EV_reactor_fiber);
  return Qnil;
}

static VALUE EV_rerun(VALUE self) {
  EV_break(self);
  EV_restart(self);
  return Qnil;
}

static VALUE EV_ref(VALUE self) {
  ev_ref(EV_DEFAULT);
  return Qnil;
}

static VALUE EV_unref(VALUE self) {
  ev_unref(EV_DEFAULT);
  return Qnil;
}

void EV_add_watcher_ref(VALUE obj) {
  rb_hash_aset(watcher_refs, rb_obj_id(obj), obj);
}

void EV_del_watcher_ref(VALUE obj) {
  rb_hash_delete(watcher_refs, rb_obj_id(obj));
}

static VALUE EV_next_tick(VALUE self) {
  VALUE proc = rb_block_proc();
  if (RTEST(proc)) {
    rb_ary_push(next_tick_items, proc);
    if (!next_tick_active) {
      next_tick_active = 1;
      ev_timer_start(EV_DEFAULT, &next_tick_timer);
    }
  }
  return Qnil;
}

static VALUE EV_snooze(VALUE self) {
  VALUE ret;
  VALUE fiber = rb_fiber_current();

  rb_ary_push(next_tick_items, fiber);
  if (!next_tick_active) {
    next_tick_active = 1;
    ev_timer_start(EV_DEFAULT, &next_tick_timer);
  }

  ret = YIELD_TO_REACTOR();
  
  // fiber is resumed, check if resumed value is an exception
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    rb_ary_delete(next_tick_items, fiber);
    return rb_funcall(ret, ID_raise, 1, ret);
  }
  else {
    return ret;
  }
}

static VALUE EV_post_fork(VALUE self) {
  ev_loop_fork(EV_DEFAULT);
  
  EV_reactor_fiber = rb_fiber_new(EV_run, Qnil);
  rb_gv_set("__reactor_fiber__", EV_reactor_fiber);
  EV_root_fiber = rb_fiber_current();

  return Qnil;
}

VALUE EV_next_tick_runner(VALUE proc) {
  if (rb_obj_is_proc(proc)) {
    rb_funcall(proc, ID_call, 1, Qtrue);
  }
  else {
    SCHEDULE_FIBER(proc, 1, rb_ivar_get(proc, ID_scheduled_value));
  }
  return Qnil;
}

void EV_next_tick_callback(ev_loop *ev_loop, struct ev_timer *timer, int revents) {
  VALUE scheduled_items = next_tick_items;
  next_tick_items = rb_ary_new();

  long len = RARRAY_LEN(scheduled_items);
  for (long i = 0; i < len; i++) {
    EV_next_tick_runner(RARRAY_AREF(scheduled_items, i));
  }

  if (rb_array_len(next_tick_items) > 0) {
    ev_timer_start(EV_DEFAULT, &next_tick_timer);
  } else {
    next_tick_active = 0;
  }
}

static VALUE EV_suspend(VALUE self) {
  if (!RTEST(rb_fiber_alive_p(EV_reactor_fiber))) {
    return Qnil;
  }

  VALUE ret = YIELD_TO_REACTOR();

  // fiber is resumed, check if resumed value is an exception
  return RTEST(rb_obj_is_kind_of(ret, rb_eException)) ? 
    rb_funcall(ret, ID_raise, 1, ret) : ret;
}

static VALUE EV_schedule_fiber(VALUE self, VALUE fiber, VALUE value) {
  rb_ivar_set(fiber, ID_scheduled_value, value);

  rb_ary_push(next_tick_items, fiber);
  if (!next_tick_active) {
    next_tick_active = 1;
    ev_timer_start(EV_DEFAULT, &next_tick_timer);
  }

  return Qnil;
}