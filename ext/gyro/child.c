#include "gyro.h"

struct Gyro_Child {
  struct  ev_child ev_child;
  int     active;
  int     pid;
  VALUE   self;
  VALUE   fiber;
};

static VALUE cGyro_Child = Qnil;

/* Allocator/deallocator */
static VALUE Gyro_Child_allocate(VALUE klass);
static void Gyro_Child_mark(void *ptr);
static void Gyro_Child_free(void *ptr);
static size_t Gyro_Child_size(const void *ptr);

/* Methods */
static VALUE Gyro_Child_initialize(VALUE self, VALUE pid);

static VALUE Gyro_Child_await(VALUE self);

void Gyro_Child_callback(struct ev_loop *ev_loop, struct ev_child *child, int revents);

/* Child encapsulates an child watcher */
void Init_Gyro_Child() {
  cGyro_Child = rb_define_class_under(mGyro, "Child", rb_cData);
  rb_define_alloc_func(cGyro_Child, Gyro_Child_allocate);

  rb_define_method(cGyro_Child, "initialize", Gyro_Child_initialize, 1);
  rb_define_method(cGyro_Child, "await", Gyro_Child_await, 0);
}

static const rb_data_type_t Gyro_Child_type = {
    "Gyro_Child",
    {Gyro_Child_mark, Gyro_Child_free, Gyro_Child_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Gyro_Child_allocate(VALUE klass) {
  struct Gyro_Child *child = (struct Gyro_Child *)xmalloc(sizeof(struct Gyro_Child));
  return TypedData_Wrap_Struct(klass, &Gyro_Child_type, child);
}

static void Gyro_Child_mark(void *ptr) {
  struct Gyro_Child *child = ptr;
  if (child->fiber != Qnil) {
    rb_gc_mark(child->fiber);
  }
}

static void Gyro_Child_free(void *ptr) {
  struct Gyro_Child *child = ptr;
  if (child->active) {
    ev_child_stop(EV_DEFAULT, &child->ev_child);
  }
  xfree(child);
}

static size_t Gyro_Child_size(const void *ptr) {
  return sizeof(struct Gyro_Child);
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

void Gyro_Child_callback(struct ev_loop *ev_loop, struct ev_child *ev_child, int revents) {
  struct Gyro_Child *child = (struct Gyro_Child*)ev_child;

  child->active = 0;
  ev_child_stop(EV_DEFAULT, ev_child);

  if (child->fiber != Qnil) {
    VALUE fiber = child->fiber;
    VALUE resume_value = INT2NUM(child->pid);
    child->fiber = Qnil;
    Gyro_schedule_fiber(fiber, resume_value);
  }
}

static VALUE Gyro_Child_await(VALUE self) {
  struct Gyro_Child *child;
  VALUE ret;
  
  GetGyro_Child(self, child);

  child->fiber = rb_fiber_current();
  child->active = 1;
  ev_child_start(EV_DEFAULT, &child->ev_child);

  ret = Gyro_await();

  // fiber is resumed, check if resumed value is an exception
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    printf("* child error\n");
    if (child->active) {
      child->active = 0;
      ev_child_stop(EV_DEFAULT, &child->ev_child);
    }
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  }
  else {
    return ret;
  }
}