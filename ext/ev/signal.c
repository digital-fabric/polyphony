#include "ev.h"

struct EV_Signal
{
    VALUE self;
    int signum;
    struct ev_signal ev_signal;
    VALUE callback;
};

static VALUE mEV = Qnil;
static VALUE cEV_Signal = Qnil;

/* Allocator/deallocator */
static VALUE EV_Signal_allocate(VALUE klass);
static void EV_Signal_mark(struct EV_Signal *signal);
static void EV_Signal_free(struct EV_Signal *signal);

/* Methods */
static VALUE EV_Signal_initialize(VALUE self, VALUE sig);

static VALUE EV_Signal_start(VALUE self);
static VALUE EV_Signal_stop(VALUE self);

void EV_Signal_callback(ev_loop *ev_loop, struct ev_signal *signal, int revents);

/* Signal encapsulates a signal watcher */
void Init_EV_Signal()
{
  mEV = rb_define_module("EV");
  cEV_Signal = rb_define_class_under(mEV, "Signal", rb_cObject);
  rb_define_alloc_func(cEV_Signal, EV_Signal_allocate);

  rb_define_method(cEV_Signal, "initialize", EV_Signal_initialize, 1);
  rb_define_method(cEV_Signal, "start", EV_Signal_start, 0);
  rb_define_method(cEV_Signal, "stop", EV_Signal_stop, 0);
}

static VALUE EV_Signal_allocate(VALUE klass)
{
  struct EV_Signal *signal = (struct EV_Signal *)xmalloc(sizeof(struct EV_Signal));

  return Data_Wrap_Struct(klass, EV_Signal_mark, EV_Signal_free, signal);
}

static void EV_Signal_mark(struct EV_Signal *signal)
{
  rb_gc_mark(signal->callback);
}

static void EV_Signal_free(struct EV_Signal *signal)
{
  ev_signal_stop(EV_DEFAULT, &signal->ev_signal);
  xfree(signal);
}

static VALUE EV_Signal_initialize(VALUE self, VALUE sig)
{
  struct EV_Signal *signal;

  Data_Get_Struct(self, struct EV_Signal, signal);

  VALUE signum = sig;

  signal->signum = NUM2INT(signum);

  if (rb_block_given_p()) {
    signal->callback = rb_block_proc();
  }

  ev_signal_init(&signal->ev_signal, EV_Signal_callback, signal->signum);

  signal->ev_signal.data = (void *)signal;

  ev_signal_start(EV_DEFAULT, &signal->ev_signal);
  EV_add_watcher_ref(self);

  return Qnil;
}

void EV_Signal_callback(ev_loop *ev_loop, struct ev_signal *signal, int revents)
{
  struct EV_Signal *signal_data = (struct EV_Signal *)signal->data;
  rb_funcall(signal_data->callback, rb_intern("call"), 1, INT2NUM(signal_data->signum));
}

static VALUE EV_Signal_start(VALUE self)
{
  struct EV_Signal *signal;
  Data_Get_Struct(self, struct EV_Signal, signal);

  ev_signal_start(EV_DEFAULT, &signal->ev_signal);
  EV_add_watcher_ref(self);

  return Qnil;
}

static VALUE EV_Signal_stop(VALUE self)
{
  struct EV_Signal *signal;
  Data_Get_Struct(self, struct EV_Signal, signal);

  ev_signal_stop(EV_DEFAULT, &signal->ev_signal);
  EV_del_watcher_ref(self);

  return Qnil;
}
