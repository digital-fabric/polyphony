#include "gyro.h"

struct Gyro_Child {
  struct  ev_child ev_child;
  struct  ev_loop *ev_loop;
  int     active;
  int     pid;
  VALUE   self;
  VALUE   fiber;
  VALUE   selector;
};

static VALUE cGyro_Child = Qnil;

static void Gyro_Child_mark(void *ptr) {
  struct Gyro_Child *child = ptr;
  if (child->fiber != Qnil) {
    rb_gc_mark(child->fiber);
  }
  if (child->selector != Qnil) {
    rb_gc_mark(child->selector);
  }
}

static void Gyro_Child_free(void *ptr) {
  struct Gyro_Child *child = ptr;
  switch (child->active) {
    case GYRO_WATCHER_POST_FORK:
      return;
    case 1:
      ev_clear_pending(child->ev_loop, &child->ev_child);
      ev_child_stop(child->ev_loop, &child->ev_child);
    default:
      xfree(child);
  }
}

static size_t Gyro_Child_size(const void *ptr) {
  return sizeof(struct Gyro_Child);
}

static const rb_data_type_t Gyro_Child_type = {
    "Gyro_Child",
    {Gyro_Child_mark, Gyro_Child_free, Gyro_Child_size,},
    0, 0, 0
};

static VALUE Gyro_Child_allocate(VALUE klass) {
  struct Gyro_Child *child = ALLOC(struct Gyro_Child);
  return TypedData_Wrap_Struct(klass, &Gyro_Child_type, child);
}

inline void child_activate(struct Gyro_Child *child) {
  if (child->active) return;

  child->active = 1;
  child->fiber = rb_fiber_current();
  child->selector = Thread_current_event_selector();
  child->ev_loop = Gyro_Selector_ev_loop(child->selector);
  Gyro_Selector_add_active_watcher(child->selector, child->self);
  ev_child_start(child->ev_loop, &child->ev_child);
}

inline void child_deactivate(struct Gyro_Child *child) {
  if (!child->active) return;

  ev_child_stop(child->ev_loop, &child->ev_child);
  Gyro_Selector_remove_active_watcher(child->selector, child->self);
  child->active = 0;
  child->ev_loop = 0;
  child->selector = Qnil;
  child->fiber = Qnil;
}

VALUE Gyro_Child_resume_value(struct ev_child *ev_child) {
  int exit_status = ev_child->rstatus >> 8; // weird, why should we do this?

  return rb_ary_new_from_args(
    2, INT2NUM(ev_child->rpid), INT2NUM(exit_status)
  );
}

void Gyro_Child_callback(struct ev_loop *ev_loop, struct ev_child *ev_child, int revents) {
  struct Gyro_Child *child = (struct Gyro_Child*)ev_child;

  VALUE resume_value = Gyro_Child_resume_value(ev_child);
  Fiber_make_runnable(child->fiber, resume_value);

  child_deactivate(child);
}

#define GetGyro_Child(obj, child) \
  TypedData_Get_Struct((obj), struct Gyro_Child, &Gyro_Child_type, (child))

static VALUE Gyro_Child_initialize(VALUE self, VALUE pid) {
  struct Gyro_Child *child;

  GetGyro_Child(self, child);

  child->self       = self;
  child->fiber      = Qnil;
  child->selector   = Qnil;
  child->pid        = NUM2INT(pid);
  child->active     = 0;
  child->ev_loop    = 0;
  
  ev_child_init(&child->ev_child, Gyro_Child_callback, child->pid, 0);

  return Qnil;
}

static VALUE Gyro_Child_await(VALUE self) {
  struct Gyro_Child *child;
  GetGyro_Child(self, child);

  child_activate(child);
  VALUE ret = Gyro_switchpoint();
  child_deactivate(child);

  TEST_RESUME_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

VALUE Gyro_Child_deactivate_post_fork(VALUE self) {
  struct Gyro_Child *child;
  GetGyro_Child(self, child);

  if (child->active)
    child->active = GYRO_WATCHER_POST_FORK;
  return self;
}

void Init_Gyro_Child() {
  cGyro_Child = rb_define_class_under(mGyro, "Child", rb_cData);
  rb_define_alloc_func(cGyro_Child, Gyro_Child_allocate);

  rb_define_method(cGyro_Child, "initialize", Gyro_Child_initialize, 1);
  rb_define_method(cGyro_Child, "await", Gyro_Child_await, 0);
  rb_define_method(cGyro_Child, "deactivate_post_fork", Gyro_Child_deactivate_post_fork, 0);
}
