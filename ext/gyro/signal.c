#include "gyro.h"

struct Gyro_Signal {
  struct  ev_signal ev_signal;
  struct  ev_loop *ev_loop;
  int     active;
  int     signum;
  VALUE   fiber;
};

static VALUE cGyro_Signal = Qnil;

static void Gyro_Signal_mark(void *ptr) {
  struct Gyro_Signal *signal = ptr;
  if (signal->fiber != Qnil) {
    rb_gc_mark(signal->fiber);
  }
}

static void Gyro_Signal_free(void *ptr) {
  struct Gyro_Signal *signal = ptr;
  if (signal->active) {
    printf("Signal watcher garbage collected while still active!\n");
    // ev_signal_stop(signal->ev_loop, &signal->ev_signal);
  }
  xfree(signal);
}

static size_t Gyro_Signal_size(const void *ptr) {
  return sizeof(struct Gyro_Signal);
}

static const rb_data_type_t Gyro_Signal_type = {
    "Gyro_Signal",
    {Gyro_Signal_mark, Gyro_Signal_free, Gyro_Signal_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Gyro_Signal_allocate(VALUE klass) {
  struct Gyro_Signal *signal = (struct Gyro_Signal *)xmalloc(sizeof(struct Gyro_Signal));
  return TypedData_Wrap_Struct(klass, &Gyro_Signal_type, signal);
}

void Gyro_Signal_callback(struct ev_loop *ev_loop, struct ev_signal *ev_signal, int revents) {
  struct Gyro_Signal *signal = (struct Gyro_Signal*)ev_signal;

  if (signal->fiber != Qnil) {
    VALUE fiber = signal->fiber;

    ev_signal_stop(signal->ev_loop, ev_signal);
    signal->active = 0;
    signal->fiber = Qnil;
    Gyro_schedule_fiber(fiber, INT2NUM(signal->signum));
  }
}

#define GetGyro_Signal(obj, signal) \
  TypedData_Get_Struct((obj), struct Gyro_Signal, &Gyro_Signal_type, (signal))

static VALUE Gyro_Signal_initialize(VALUE self, VALUE sig) {
  struct Gyro_Signal *signal;
  VALUE signum = sig;
 
  GetGyro_Signal(self, signal);
  signal->signum = NUM2INT(signum);

  ev_signal_init(&signal->ev_signal, Gyro_Signal_callback, signal->signum);

  return Qnil;
}

static VALUE Gyro_Signal_await(VALUE self) {
  struct Gyro_Signal *signal;
  VALUE ret;
  
  GetGyro_Signal(self, signal);

  signal->fiber = rb_fiber_current();
  signal->active = 1;
  signal->ev_loop = Gyro_Selector_current_thread_ev_loop();
  ev_signal_start(signal->ev_loop, &signal->ev_signal);

  ret = Fiber_await();
  RB_GC_GUARD(ret);

  if (signal->active) {
    signal->active = 0;
    signal->fiber = Qnil;
    ev_signal_stop(signal->ev_loop, &signal->ev_signal);
  }

  // fiber is resumed, check if resumed value is an exception
  signal->fiber = Qnil;
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    return rb_funcall(rb_mKernel, ID_raise, 1, ret);
  }
  else
    return ret;
}

void Init_Gyro_Signal() {
  cGyro_Signal = rb_define_class_under(mGyro, "Signal", rb_cData);
  rb_define_alloc_func(cGyro_Signal, Gyro_Signal_allocate);

  rb_define_method(cGyro_Signal, "initialize", Gyro_Signal_initialize, 1);
  rb_define_method(cGyro_Signal, "await", Gyro_Signal_await, 0);
}
