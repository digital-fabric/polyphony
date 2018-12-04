#include "ev.h"

struct EV_Child {
  struct  ev_child ev_child;
  int     active;
  int     pid;
  VALUE   self;
  VALUE   callback;
  VALUE   fiber;
};

static VALUE mEV = Qnil;
static VALUE cEV_Child = Qnil;

/* Allocator/deallocator */
static VALUE EV_Child_allocate(VALUE klass);
static void EV_Child_mark(struct EV_Child *child);
static void EV_Child_free(struct EV_Child *child);
static size_t EV_Child_size(struct EV_Child *child);

/* Methods */
static VALUE EV_Child_initialize(VALUE self, VALUE pid);

static VALUE EV_Child_start(VALUE self);
static VALUE EV_Child_stop(VALUE self);
static VALUE EV_Child_await(VALUE self);

void EV_Child_callback(ev_loop *ev_loop, struct ev_child *child, int revents);

static ID ID_call = Qnil;

/* Child encapsulates an child watcher */
void Init_EV_Child() {
  mEV = rb_define_module("EV");
  cEV_Child = rb_define_class_under(mEV, "Child", rb_cData);
  rb_define_alloc_func(cEV_Child, EV_Child_allocate);

  rb_define_method(cEV_Child, "initialize", EV_Child_initialize, 1);
  rb_define_method(cEV_Child, "start", EV_Child_start, 0);
  rb_define_method(cEV_Child, "stop", EV_Child_stop, 0);
  rb_define_method(cEV_Child, "await", EV_Child_await, 0);
  

  ID_call = rb_intern("call");
}

static const rb_data_type_t EV_Child_type = {
    "EV_Child",
    {EV_Child_mark, EV_Child_free, EV_Child_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE EV_Child_allocate(VALUE klass) {
  struct EV_Child *child = (struct EV_Child *)xmalloc(sizeof(struct EV_Child));
  return TypedData_Wrap_Struct(klass, &EV_Child_type, child);
}

static void EV_Child_mark(struct EV_Child *child) {
  if (child->callback != Qnil) {
    rb_gc_mark(child->callback);
  }
  if (child->fiber != Qnil) {
    rb_gc_mark(child->fiber);
  }
}

static void EV_Child_free(struct EV_Child *child) {
  if (child->active) {
    ev_child_stop(EV_DEFAULT, &child->ev_child);
  }
  xfree(child);
}

static size_t EV_Child_size(struct EV_Child *child) {
  return sizeof(struct EV_Child);
}

#define GetEV_Child(obj, child) \
  TypedData_Get_Struct((obj), struct EV_Child, &EV_Child_type, (child))

static VALUE EV_Child_initialize(VALUE self, VALUE pid) {
  struct EV_Child *child;

  GetEV_Child(self, child);

  child->self     = self;
  child->callback = Qnil;
  child->fiber    = Qnil;
  child->pid      = NUM2INT(pid);
  child->active   = 0;
  
  ev_child_init(&child->ev_child, EV_Child_callback, child->pid, 0);

  return Qnil;
}

void EV_Child_callback(ev_loop *ev_loop, struct ev_child *ev_child, int revents) {
  VALUE fiber;
  VALUE resume_value;
  struct EV_Child *child = (struct EV_Child*)ev_child;
  resume_value = INT2NUM(child->pid);

  child->active = 0;
  ev_child_stop(EV_DEFAULT, ev_child);
  EV_del_watcher_ref(child->self);

  if (child->fiber != Qnil) {
    fiber = child->fiber;
    child->fiber = Qnil;
    rb_fiber_resume(fiber, 1, &resume_value);
  }
  else if (child->callback != Qnil) {
    rb_funcall(child->callback, ID_call, 1, resume_value);
  }
}

static VALUE EV_Child_start(VALUE self) {
  struct EV_Child *child;
  GetEV_Child(self, child);

  if (rb_block_given_p()) {
    child->callback = rb_block_proc();
  }

  if (!child->active) {
    ev_child_start(EV_DEFAULT, &child->ev_child);
    child->active = 1;
    EV_add_watcher_ref(self);
  }

  return self;
}

static VALUE EV_Child_stop(VALUE self) {
  struct EV_Child *child;
  GetEV_Child(self, child);

  if (child->active) {
    ev_child_stop(EV_DEFAULT, &child->ev_child);
    child->active = 0;
    EV_del_watcher_ref(self);
  }

  return self;
}

static VALUE EV_Child_await(VALUE self) {
  struct EV_Child *child;
  VALUE ret;
  
  GetEV_Child(self, child);

  child->fiber = rb_fiber_current();
  child->active = 1;
  ev_child_start(EV_DEFAULT, &child->ev_child);
  EV_add_watcher_ref(self);

  ret = rb_fiber_yield(0, 0);

  // fiber is resumed, check if resumed value is an exception
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    if (child->active) {
      child->active = 0;
      ev_child_stop(EV_DEFAULT, &child->ev_child);
    }
    return rb_funcall(ret, rb_intern("raise"), 1, ret);
  }
  else {
    return ret;
  }
}