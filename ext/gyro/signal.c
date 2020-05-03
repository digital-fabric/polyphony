#include "gyro.h"

struct Gyro_Signal {
  GYRO_WATCHER_DECL(ev_signal);
  int signum;
};

static VALUE cGyro_Signal = Qnil;

static void Gyro_Signal_mark(void *ptr) {
  struct Gyro_Signal *signal = ptr;
  GYRO_WATCHER_MARK(signal);
}

static void Gyro_Signal_free(void *ptr) {
  struct Gyro_Signal *signal = ptr;
  GYRO_WATCHER_FREE(signal);
}

static size_t Gyro_Signal_size(const void *ptr) {
  return sizeof(struct Gyro_Signal);
}

static const rb_data_type_t Gyro_Signal_type = {
    "Gyro_Signal",
    {Gyro_Signal_mark, Gyro_Signal_free, Gyro_Signal_size,},
    0, 0, 0
};

static VALUE Gyro_Signal_allocate(VALUE klass) {
  struct Gyro_Signal *signal = ALLOC(struct Gyro_Signal);
  return TypedData_Wrap_Struct(klass, &Gyro_Signal_type, signal);
}

inline void signal_activate(struct Gyro_Signal *signal) {
  if (signal->active) return;

  signal->active = 1;
  signal->fiber = rb_fiber_current();
  signal->selector = Thread_current_event_selector();
  signal->ev_loop = Gyro_Selector_ev_loop(signal->selector);
  Gyro_Selector_add_active_watcher(signal->selector, signal->self);
  ev_signal_start(signal->ev_loop, &signal->ev_signal);
}

inline void signal_deactivate(struct Gyro_Signal *signal) {
  if (!signal->active) return;

  ev_signal_stop(signal->ev_loop, &signal->ev_signal);
  Gyro_Selector_remove_active_watcher(signal->selector, signal->self);
  signal->active = 0;
  signal->ev_loop = 0;
  signal->selector = Qnil;
  signal->fiber = Qnil;
}

void Gyro_Signal_callback(struct ev_loop *ev_loop, struct ev_signal *ev_signal, int revents) {
  struct Gyro_Signal *signal = (struct Gyro_Signal*)ev_signal;

  Fiber_make_runnable(signal->fiber, INT2NUM(signal->signum));
  signal_deactivate(signal);
}

#define GetGyro_Signal(obj, signal) \
  TypedData_Get_Struct((obj), struct Gyro_Signal, &Gyro_Signal_type, (signal))

static VALUE Gyro_Signal_initialize(VALUE self, VALUE sig) {
  struct Gyro_Signal *signal;
  VALUE signum = sig;

  GetGyro_Signal(self, signal);
  GYRO_WATCHER_INITIALIZE(signal, self);
  signal->signum = NUM2INT(signum);
  ev_signal_init(&signal->ev_signal, Gyro_Signal_callback, signal->signum);

  return Qnil;
}

static VALUE Gyro_Signal_await(VALUE self) {
  struct Gyro_Signal *signal;
  VALUE ret;
  GetGyro_Signal(self, signal);

  signal_activate(signal);
  ret = Gyro_switchpoint();
  signal_deactivate(signal);

  TEST_RESUME_EXCEPTION(ret);
  RB_GC_GUARD(ret);
  return ret;
}

void Init_Gyro_Signal() {
  cGyro_Signal = rb_define_class_under(mGyro, "Signal", rb_cData);
  rb_define_alloc_func(cGyro_Signal, Gyro_Signal_allocate);

  rb_define_method(cGyro_Signal, "initialize", Gyro_Signal_initialize, 1);
  rb_define_method(cGyro_Signal, "await", Gyro_Signal_await, 0);
}
