#include "gyro.h"

struct Gyro_Child {
  GYRO_WATCHER_DECL(ev_child);
  int pid;
};

static VALUE cGyro_Child = Qnil;

static void Gyro_Child_mark(void *ptr) {
  struct Gyro_Child *child = ptr;
  GYRO_WATCHER_MARK(child);
}

static void Gyro_Child_free(void *ptr) {
  struct Gyro_Child *child = ptr;
  GYRO_WATCHER_FREE(child);
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
  GYRO_WATCHER_INITIALIZE(child, self);
  child->pid = NUM2INT(pid);
  ev_child_init(&child->ev_child, Gyro_Child_callback, child->pid, 0);

  return Qnil;
}

static VALUE Gyro_Child_await(VALUE self) {
  struct Gyro_Child *child;
  VALUE ret;
  GetGyro_Child(self, child);

  child_activate(child);
  ret = Gyro_switchpoint();
  child_deactivate(child);

  TEST_RESUME_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

void Init_Gyro_Child() {
  cGyro_Child = rb_define_class_under(mGyro, "Child", rb_cData);
  rb_define_alloc_func(cGyro_Child, Gyro_Child_allocate);

  rb_define_method(cGyro_Child, "initialize", Gyro_Child_initialize, 1);
  rb_define_method(cGyro_Child, "await", Gyro_Child_await, 0);
}
