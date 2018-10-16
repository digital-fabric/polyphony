#include "ev.h"

static VALUE mEV = Qnil;

static VALUE EV_run(VALUE self);
static VALUE EV_break(VALUE self);

static VALUE EV_ref(VALUE self);
static VALUE EV_unref(VALUE self);

static VALUE EV_next_tick(VALUE self);

static VALUE watcher_refs;
static VALUE next_tick_procs;

static struct ev_timer next_tick_timer;
static int next_tick_active;
void EV_next_tick_callback(ev_loop *ev_loop, struct ev_timer *timer, int revents);

void Init_EV() {
  mEV = rb_define_module("EV");

  rb_define_singleton_method(mEV, "run", EV_run, 0);
  rb_define_singleton_method(mEV, "break", EV_break, 0);
  rb_define_singleton_method(mEV, "ref", EV_ref, 0);
  rb_define_singleton_method(mEV, "unref", EV_unref, 0);
  rb_define_singleton_method(mEV, "next_tick", EV_next_tick, 0);

  ID_call = rb_intern("call");
  ID_each = rb_intern("each");

  watcher_refs = rb_hash_new();
  rb_global_variable(&watcher_refs);

  next_tick_procs = rb_ary_new();
  rb_global_variable(&next_tick_procs);

  ev_timer_init(&next_tick_timer, EV_next_tick_callback, 0., 0.);
  next_tick_active = 0;
}

static VALUE EV_run(VALUE self) {
  ev_run(EV_DEFAULT, 0);
  return Qnil;
}

static VALUE EV_break(VALUE self) {
  ev_break(EV_DEFAULT, EVBREAK_ALL);
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
    rb_ary_push(next_tick_procs, proc);
    if (!next_tick_active) {
      next_tick_active = 1;
      ev_timer_start(EV_DEFAULT, &next_tick_timer);
    }
  }
  return Qnil;
}

VALUE EV_next_tick_caller(VALUE proc, VALUE data, int argc, VALUE* argv) {
  rb_funcall(proc, ID_call, 1, Qtrue);
  return Qnil;
}

void EV_next_tick_callback(ev_loop *ev_loop, struct ev_timer *timer, int revents) {
  VALUE scheduled_procs = next_tick_procs;
  next_tick_procs = rb_ary_new();
  rb_block_call(scheduled_procs, ID_each, 0, NULL, EV_next_tick_caller, Qnil);
  if (rb_array_len(next_tick_procs) > 0) {
    ev_timer_start(EV_DEFAULT, &next_tick_timer);
  } else {
    next_tick_active = 0;
  }
}
