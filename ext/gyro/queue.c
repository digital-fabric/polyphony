#include "gyro.h"

struct Gyro_Queue {
  VALUE self;
  VALUE queue;
  VALUE wait_queue;
};

VALUE cGyro_Queue = Qnil;

static void Gyro_Queue_mark(void *ptr) {
  struct Gyro_Queue *queue = ptr;
  if (queue->queue != Qnil) {
    rb_gc_mark(queue->queue);
  }
  if (queue->wait_queue != Qnil) {
    rb_gc_mark(queue->wait_queue);
  }
}

static void Gyro_Queue_free(void *ptr) {
  struct Gyro_Queue *queue = ptr;
  xfree(queue);
}

static size_t Gyro_Queue_size(const void *ptr) {
  return sizeof(struct Gyro_Queue);
}

static const rb_data_type_t Gyro_Queue_type = {
    "Gyro_Queue",
    {Gyro_Queue_mark, Gyro_Queue_free, Gyro_Queue_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE Gyro_Queue_allocate(VALUE klass) {
  struct Gyro_Queue *queue = (struct Gyro_Queue *)xmalloc(sizeof(struct Gyro_Queue));
  return TypedData_Wrap_Struct(klass, &Gyro_Queue_type, queue);
}
#define GetGyro_Queue(obj, queue) \
  TypedData_Get_Struct((obj), struct Gyro_Queue, &Gyro_Queue_type, (queue))

static VALUE Gyro_Queue_initialize(VALUE self) {
  struct Gyro_Queue *queue;
  GetGyro_Queue(self, queue);

  queue->self       = self;
  queue->queue      = rb_ary_new();
  queue->wait_queue = rb_ary_new();
  
  return Qnil;
}

VALUE Gyro_Queue_push(VALUE self, VALUE value) {
  struct Gyro_Queue *queue;
  GetGyro_Queue(self, queue);

  if (RARRAY_LEN(queue->wait_queue) > 0) {
    VALUE async = rb_ary_shift(queue->wait_queue);
    return rb_funcall(async, ID_signal_bang, 1, value);
  }
  
  rb_ary_push(queue->queue, value);
  return self;
}

VALUE Gyro_Queue_shift(VALUE self) {
  struct Gyro_Queue *queue;
  GetGyro_Queue(self, queue);

  if (RARRAY_LEN(queue->queue) > 0) {
    return rb_ary_shift(queue->queue);
  }
  
  VALUE async = rb_funcall(cGyro_Async, ID_new, 0);
  rb_ary_push(queue->wait_queue, async);
  return Gyro_Async_await(async);
}

VALUE Gyro_Queue_shift_all(VALUE self) {
  struct Gyro_Queue *queue;
  GetGyro_Queue(self, queue);

  if (rb_block_given_p()) {
    while (RARRAY_LEN(queue->queue) > 0) {
      rb_yield(rb_ary_shift(queue->queue));
    }
  }
  else {
    rb_ary_clear(queue->queue);
  }

  return self;
}

void Init_Gyro_Queue() {
  cGyro_Queue = rb_define_class_under(mGyro, "Queue", rb_cData);
  rb_define_alloc_func(cGyro_Queue, Gyro_Queue_allocate);

  rb_define_method(cGyro_Queue, "initialize", Gyro_Queue_initialize, 0);
  rb_define_method(cGyro_Queue, "push", Gyro_Queue_push, 1);
  rb_define_method(cGyro_Queue, "<<", Gyro_Queue_push, 1);

  rb_define_method(cGyro_Queue, "pop", Gyro_Queue_shift, 0);
  rb_define_method(cGyro_Queue, "shift", Gyro_Queue_shift, 0);

  rb_define_method(cGyro_Queue, "shift_each", Gyro_Queue_shift_all, 0);
}
