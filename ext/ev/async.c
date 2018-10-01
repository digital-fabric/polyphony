#include "ev.h"

static VALUE mEV = Qnil;
static VALUE cEV_Async = Qnil;

/* Allocator/deallocator */
static VALUE EV_Async_allocate(VALUE klass);
static void EV_Async_mark(struct EV_Async *async);
static void EV_Async_free(struct EV_Async *async);

/* Methods */
static VALUE EV_Async_initialize(VALUE self);

static VALUE EV_Async_start(VALUE self);
static VALUE EV_Async_stop(VALUE self);
static VALUE EV_Async_signal(VALUE self);

void EV_Async_callback(ev_loop *ev_loop, struct ev_async *async, int revents);

/* async encapsulates an async watcher */
void Init_EV_Async()
{
  mEV = rb_define_module("EV");
  
  cEV_Async = rb_define_class_under(mEV, "Async", rb_cObject);
  rb_define_alloc_func(cEV_Async, EV_Async_allocate);

  rb_define_method(cEV_Async, "initialize", EV_Async_initialize, 0);
  rb_define_method(cEV_Async, "start", EV_Async_start, 0);
  rb_define_method(cEV_Async, "stop", EV_Async_stop, 0);
  rb_define_method(cEV_Async, "signal!", EV_Async_signal, 0);
}

static VALUE EV_Async_allocate(VALUE klass)
{
  struct EV_Async *async = (struct EV_Async *)xmalloc(sizeof(struct EV_Async));

  return Data_Wrap_Struct(klass, EV_Async_mark, EV_Async_free, async);
}

static void EV_Async_mark(struct EV_Async *async)
{
  rb_gc_mark(async->callback);
}

static void EV_Async_free(struct EV_Async *async)
{
  xfree(async);
}

static VALUE EV_Async_initialize(VALUE self)
{
  struct EV_Async *async;

  Data_Get_Struct(self, struct EV_Async, async);

  if (rb_block_given_p()) {
    async->callback = rb_block_proc();
  }

  ev_async_init(&async->ev_async, EV_Async_callback);

  async->self = self;
  async->ev_async.data = (void *)async;

  ev_async_start(EV_DEFAULT, &async->ev_async);

  return Qnil;
}

/* libev callback fired on IO event */
void EV_Async_callback(ev_loop *ev_loop, struct ev_async *async, int revents)
{
  struct EV_Async *async_data = (struct EV_Async *)async->data;
  rb_funcall(async_data->callback, rb_intern("call"), 1, Qtrue);
}

static VALUE EV_Async_start(VALUE self)
{
  struct EV_Async *async;
  Data_Get_Struct(self, struct EV_Async, async);

  ev_async_start(EV_DEFAULT, &async->ev_async);

  return Qnil;
}

static VALUE EV_Async_stop(VALUE self)
{
  struct EV_Async *async;
  Data_Get_Struct(self, struct EV_Async, async);

  ev_async_stop(EV_DEFAULT, &async->ev_async);

  return Qnil;
}

static VALUE EV_Async_signal(VALUE self)
{
  struct EV_Async *async;
  Data_Get_Struct(self, struct EV_Async, async);

  ev_async_send(EV_DEFAULT, &async->ev_async);

  return Qnil;
}
