#include "gyro.h"

struct Gyro_Child {
  struct  ev_child ev_child;
  struct  ev_loop *ev_loop;
  int     active;
  int     pid;
  VALUE   self;
  VALUE   fiber;
};

static VALUE cGyro_Child = Qnil;

static void Gyro_Child_mark(void *ptr) {
  struct Gyro_Child *child = ptr;
  if (child->fiber != Qnil) {
    rb_gc_mark(child->fiber);
  }
}

static void Gyro_Child_free(void *ptr) {
  struct Gyro_Child *child = ptr;
  if (child->active) {
    printf("Child watcher garbage collected while still active!\n");
  }
  xfree(child);
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

void Gyro_Child_callback(struct ev_loop *ev_loop, struct ev_child *ev_child, int revents) {
  struct Gyro_Child *child = (struct Gyro_Child*)ev_child;

  child->active = 0;
  ev_child_stop(child->ev_loop, ev_child);

  if (child->fiber != Qnil) {
    VALUE fiber = child->fiber;
    int exit_status = ev_child->rstatus >> 8; // weird, why should we do this?

    VALUE resume_value = rb_ary_new_from_args(
      2, INT2NUM(ev_child->rpid), INT2NUM(exit_status)
    );
    child->fiber = Qnil;
    Gyro_schedule_fiber(fiber, resume_value);
  }
}

#define GetGyro_Child(obj, child) \
  TypedData_Get_Struct((obj), struct Gyro_Child, &Gyro_Child_type, (child))

static VALUE Gyro_Child_initialize(VALUE self, VALUE pid) {
  struct Gyro_Child *child;

  GetGyro_Child(self, child);

  child->self     = self;
  child->fiber    = Qnil;
  child->pid      = NUM2INT(pid);
  child->active   = 0;
  
  ev_child_init(&child->ev_child, Gyro_Child_callback, child->pid, 0);

  return Qnil;
}

static VALUE Gyro_Child_await(VALUE self) {
  struct Gyro_Child *child;
  VALUE ret;
  
  GetGyro_Child(self, child);

  if (child->active)
  child->active = 1;
  child->fiber = rb_fiber_current();
  child->ev_loop = Gyro_Selector_current_thread_ev_loop();
  ev_child_start(child->ev_loop, &child->ev_child);

  ret = Fiber_await();
  RB_GC_GUARD(ret);

  if (child->active) {
    child->active = 0;
    child->fiber = Qnil;
    ev_child_stop(child->ev_loop, &child->ev_child);
  }

  // fiber is resumed, check if resumed value is an exception
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  }
  else {
    return ret;
  }
}

void Init_Gyro_Child() {
  cGyro_Child = rb_define_class_under(mGyro, "Child", rb_cData);
  rb_define_alloc_func(cGyro_Child, Gyro_Child_allocate);

  rb_define_method(cGyro_Child, "initialize", Gyro_Child_initialize, 1);
  rb_define_method(cGyro_Child, "await", Gyro_Child_await, 0);
}
