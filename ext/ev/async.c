#include "ev.h"

struct EV_Async {
  struct  ev_async ev_async;
  int     active;
  VALUE   callback;
  VALUE   fiber;
};

static VALUE mEV = Qnil;
static VALUE cEV_Async = Qnil;

/* Allocator/deallocator */
static VALUE EV_Async_allocate(VALUE klass);
static void EV_Async_mark(void *ptr);
static void EV_Async_free(void *ptr);
static size_t EV_Async_size(const void *ptr);

/* Methods */
static VALUE EV_Async_initialize(VALUE self);

static VALUE EV_Async_start(VALUE self);
static VALUE EV_Async_stop(VALUE self);
static VALUE EV_Async_signal(VALUE self);
static VALUE EV_Async_await(VALUE self);

void EV_Async_callback(ev_loop *ev_loop, struct ev_async *async, int revents);

/* async encapsulates an async watcher */
void Init_EV_Async() {
  mEV = rb_define_module("EV");
  
  cEV_Async = rb_define_class_under(mEV, "Async", rb_cData);
  rb_define_alloc_func(cEV_Async, EV_Async_allocate);

  rb_define_method(cEV_Async, "initialize", EV_Async_initialize, 0);
  rb_define_method(cEV_Async, "start", EV_Async_start, 0);
  rb_define_method(cEV_Async, "stop", EV_Async_stop, 0);
  rb_define_method(cEV_Async, "signal!", EV_Async_signal, 0);
  rb_define_method(cEV_Async, "await", EV_Async_await, 0);
}

static const rb_data_type_t EV_Async_type = {
    "EV_Async",
    {EV_Async_mark, EV_Async_free, EV_Async_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE EV_Async_allocate(VALUE klass) {
  struct EV_Async *async = (struct EV_Async *)xmalloc(sizeof(struct EV_Async));
  return TypedData_Wrap_Struct(klass, &EV_Async_type, async);
}

static void EV_Async_mark(void *ptr) {
  struct EV_Async *async = ptr;
  if (async->callback != Qnil) {
    rb_gc_mark(async->callback);
  }
  if (async->fiber != Qnil) {
    rb_gc_mark(async->fiber);
  }
}

static void EV_Async_free(void *ptr) {
  struct EV_Async *async = ptr;
  ev_async_stop(EV_DEFAULT, &async->ev_async);
  xfree(async);
}

static size_t EV_Async_size(const void *ptr) {
  return sizeof(struct EV_Async);
}

#define GetEV_Async(obj, async) \
  TypedData_Get_Struct((obj), struct EV_Async, &EV_Async_type, (async))

static VALUE EV_Async_initialize(VALUE self) {
  struct EV_Async *async;
  GetEV_Async(self, async);

  if (rb_block_given_p()) {
    async->callback = rb_block_proc();
  }
  async->fiber = Qnil;

  ev_async_init(&async->ev_async, EV_Async_callback);

  async->active = 1;
  ev_async_start(EV_DEFAULT, &async->ev_async);

  return Qnil;
}

void EV_Async_callback(ev_loop *ev_loop, struct ev_async *ev_async, int revents) {
  VALUE fiber;
  struct EV_Async *async = (struct EV_Async*)ev_async;

  if (async->fiber != Qnil) {
    async->active = 0;
    fiber = async->fiber;
    async->fiber = Qnil;
    SCHEDULE_FIBER(fiber, 0);
  }
  else if (async->callback != Qnil) {
    rb_funcall(async->callback, ID_call, 1, Qtrue);
  }
}

static VALUE EV_Async_start(VALUE self) {
  struct EV_Async *async;
  GetEV_Async(self, async);

  if (!async->active) {
    ev_async_start(EV_DEFAULT, &async->ev_async);
    async->active = 1;
  }

  return self;
}

static VALUE EV_Async_stop(VALUE self) {
  struct EV_Async *async;
  GetEV_Async(self, async);

  if (async->active) {
    ev_async_stop(EV_DEFAULT, &async->ev_async);
    async->active = 0;
  }

  return self;
}

static VALUE EV_Async_signal(VALUE self) {
  struct EV_Async *async;
  GetEV_Async(self, async);

  ev_async_send(EV_DEFAULT, &async->ev_async);

  return Qnil;
}

static VALUE EV_Async_await(VALUE self) {
  struct EV_Async *async;
  VALUE ret;
  
  GetEV_Async(self, async);

  async->fiber = rb_fiber_current();
  if (!async->active) {
    async->active = 1;
    ev_async_start(EV_DEFAULT, &async->ev_async);
  }

  ret = YIELD_TO_REACTOR();

  // fiber is resumed
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    if (async->active) {
      async->active = 0;
      ev_async_stop(EV_DEFAULT, &async->ev_async);
    }
    return rb_funcall(ret, ID_raise, 1, ret);
  }
  else {
    return Qnil;
  }
}