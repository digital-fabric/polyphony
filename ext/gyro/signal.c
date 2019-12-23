#include "gyro.h"

struct Gyro_Signal {
  struct  ev_signal ev_signal;
  int     active;
  int     signum;
  VALUE   callback;
};

static VALUE cGyro_Signal = Qnil;

/* Allocator/deallocator */
static VALUE Gyro_Signal_allocate(VALUE klass);
static void Gyro_Signal_mark(void *ptr);
static void Gyro_Signal_free(void *ptr);
static size_t Gyro_Signal_size(const void *ptr);

/* Methods */
static VALUE Gyro_Signal_initialize(VALUE self, VALUE sig);

static VALUE Gyro_Signal_start(VALUE self);
static VALUE Gyro_Signal_stop(VALUE self);

void Gyro_Signal_callback(struct ev_loop *ev_loop, struct ev_signal *signal, int revents);

/* Signal encapsulates a signal watcher */
void Init_Gyro_Signal() {
  cGyro_Signal = rb_define_class_under(mGyro, "Signal", rb_cData);
  rb_define_alloc_func(cGyro_Signal, Gyro_Signal_allocate);

  rb_define_method(cGyro_Signal, "initialize", Gyro_Signal_initialize, 1);
  rb_define_method(cGyro_Signal, "start", Gyro_Signal_start, 0);
  rb_define_method(cGyro_Signal, "stop", Gyro_Signal_stop, 0);
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

static void Gyro_Signal_mark(void *ptr) {
  struct Gyro_Signal *signal = ptr;
  if (signal->callback != Qnil) {
    rb_gc_mark(signal->callback);
  }
}

static void Gyro_Signal_free(void *ptr) {
  struct Gyro_Signal *signal = ptr;
  ev_signal_stop(EV_DEFAULT, &signal->ev_signal);
  xfree(signal);
}

static size_t Gyro_Signal_size(const void *ptr) {
  return sizeof(struct Gyro_Signal);
}

#define GetGyro_Signal(obj, signal) \
  TypedData_Get_Struct((obj), struct Gyro_Signal, &Gyro_Signal_type, (signal))

static VALUE Gyro_Signal_initialize(VALUE self, VALUE sig) {
  struct Gyro_Signal *signal;
  VALUE signum = sig;
 
  GetGyro_Signal(self, signal);
  signal->signum = NUM2INT(signum);

  if (rb_block_given_p()) {
    signal->callback = rb_block_proc();
  }

  ev_signal_init(&signal->ev_signal, Gyro_Signal_callback, signal->signum);

  signal->active = 1;
  Gyro_ref_count_incr();
  ev_signal_start(EV_DEFAULT, &signal->ev_signal);

  return Qnil;
}

void Gyro_Signal_callback(struct ev_loop *ev_loop, struct ev_signal *ev_signal, int revents) {
  struct Gyro_Signal *signal = (struct Gyro_Signal*)ev_signal;

  if (signal->callback != Qnil) {
    rb_funcall(signal->callback, ID_call, 1, INT2NUM(signal->signum));
  }
}

static VALUE Gyro_Signal_start(VALUE self) {
  struct Gyro_Signal *signal;
  GetGyro_Signal(self, signal);

  if (!signal->active) {
    Gyro_ref_count_incr();
    ev_signal_start(EV_DEFAULT, &signal->ev_signal);
    signal->active = 1;
  }

  return self;
}

static VALUE Gyro_Signal_stop(VALUE self) {
  struct Gyro_Signal *signal;
  GetGyro_Signal(self, signal);

  if (signal->active) {
    Gyro_ref_count_decr();
    ev_signal_stop(EV_DEFAULT, &signal->ev_signal);
    signal->active = 0;
  }

  return self;
}