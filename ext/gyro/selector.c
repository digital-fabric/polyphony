#include "gyro.h"

struct Gyro_Selector {
  struct  ev_loop *ev_loop;
};

VALUE cGyro_Selector = Qnil;

static void Gyro_Selector_mark(void *ptr) {
  // struct Gyro_Selector *selector = ptr;
}

static void Gyro_Selector_free(void *ptr) {
  struct Gyro_Selector *selector = ptr;
  if (selector->ev_loop && !ev_is_default_loop(selector->ev_loop)) {
    // rb_warn("Selector garbage collected before being stopped!\n");
    ev_loop_destroy(selector->ev_loop);
  }
  xfree(selector);
}

static size_t Gyro_Selector_size(const void *ptr) {
  return sizeof(struct Gyro_Selector);
}

static const rb_data_type_t Gyro_Selector_type = {
    "Gyro_Selector",
    {Gyro_Selector_mark, Gyro_Selector_free, Gyro_Selector_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Gyro_Selector_allocate(VALUE klass) {
  struct Gyro_Selector *selector = (struct Gyro_Selector *)xmalloc(sizeof(struct Gyro_Selector));
  return TypedData_Wrap_Struct(klass, &Gyro_Selector_type, selector);
}

#define GetGyro_Selector(obj, selector) \
  TypedData_Get_Struct((obj), struct Gyro_Selector, &Gyro_Selector_type, (selector))

inline struct ev_loop *Gyro_Selector_current_thread_ev_loop() {
  struct Gyro_Selector *selector;
  GetGyro_Selector(Thread_current_event_selector(), selector);

  return selector->ev_loop;
}

long Gyro_Selector_pending_count(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  return ev_pending_count(selector->ev_loop);
}

static VALUE Gyro_Selector_initialize(VALUE self, VALUE thread) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  int use_default_loop = (rb_thread_current() == rb_thread_main());
  selector->ev_loop = use_default_loop ? EV_DEFAULT : ev_loop_new(EVFLAG_NOSIGMASK);
  
  return Qnil;
}

inline VALUE Gyro_Selector_run(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);
  if (selector->ev_loop) {
    ev_run(selector->ev_loop, EVRUN_ONCE);
  }
  return Qnil;
}

VALUE Gyro_Selector_stop(VALUE self) {
  struct Gyro_Selector *selector;
  GetGyro_Selector(self, selector);

  if (selector->ev_loop && !ev_is_default_loop(selector->ev_loop)) {
    ev_loop_destroy(selector->ev_loop);
    selector->ev_loop = 0;
  }
  return Qnil;
}

inline static VALUE Gyro_Selector_wait_readable(VALUE self, VALUE io) {
  VALUE watcher = IO_read_watcher(io);
  return Gyro_IO_await(watcher);
}

inline static VALUE Gyro_Selector_wait_writable(VALUE self, VALUE io) {
  VALUE watcher = IO_write_watcher(io);
  return Gyro_IO_await(watcher);
}

inline static VALUE Gyro_Selector_wait_timeout(VALUE self, VALUE duration) {
  VALUE watcher = rb_funcall(cGyro_Timer, ID_new, 2, duration, Qnil);
  return Gyro_Timer_await(watcher);
}

void Init_Gyro_Selector() {
  cGyro_Selector = rb_define_class_under(mGyro, "Selector", rb_cData);
  rb_define_alloc_func(cGyro_Selector, Gyro_Selector_allocate);

  rb_define_method(cGyro_Selector, "initialize", Gyro_Selector_initialize, 1);
  rb_define_method(cGyro_Selector, "run", Gyro_Selector_run, 0);
  rb_define_method(cGyro_Selector, "stop", Gyro_Selector_stop, 0);
  rb_define_method(cGyro_Selector, "wait_readable", Gyro_Selector_wait_readable, 1);
  rb_define_method(cGyro_Selector, "wait_writable", Gyro_Selector_wait_writable, 1);
  rb_define_method(cGyro_Selector, "wait_timeout", Gyro_Selector_wait_timeout, 1);
}
