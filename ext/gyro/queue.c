#include "gyro.h"

typedef struct queue {
  VALUE items;
  VALUE shift_waiters;
} Gyro_Queue_t;

VALUE cGyro_Queue = Qnil;

static void Gyro_Queue_mark(void *ptr) {
  Gyro_Queue_t *queue = ptr;
  if (queue->items != Qnil) {
    rb_gc_mark(queue->items);
  }
  if (queue->shift_waiters != Qnil) {
    rb_gc_mark(queue->shift_waiters);
  }
}

static size_t Gyro_Queue_size(const void *ptr) {
  return sizeof(Gyro_Queue_t);
}

static const rb_data_type_t Gyro_Queue_type = {
  "Gyro_Queue",
  {Gyro_Queue_mark, RUBY_DEFAULT_FREE, Gyro_Queue_size,},
  0, 0, 0
};

static VALUE Gyro_Queue_allocate(VALUE klass) {
  Gyro_Queue_t *queue;
  // return Data_Make_Struct(klass, Gyro_Queue_t, Gyro_Queue_mark, free, queue);

  queue = ALLOC(Gyro_Queue_t);
  // struct Gyro_Queue *queue = ALLOC(struct Gyro_Queue);
  return TypedData_Wrap_Struct(klass, &Gyro_Queue_type, queue);
}

#define GetGyro_Queue(obj, queue) \
  TypedData_Get_Struct((obj), Gyro_Queue_t, &Gyro_Queue_type, (queue))

static VALUE Gyro_Queue_initialize(VALUE self) {
  Gyro_Queue_t *queue;
  GetGyro_Queue(self, queue);

  queue->items = rb_ary_new();
  queue->shift_waiters = rb_ary_new();

  return self;
}

VALUE Gyro_Queue_push(VALUE self, VALUE value) {
  Gyro_Queue_t *queue;
  GetGyro_Queue(self, queue);

  if (RARRAY_LEN(queue->shift_waiters) > 0) {
    VALUE watcher = rb_ary_shift(queue->shift_waiters);
    rb_funcall(watcher, ID_signal, 1, Qnil);
  }

  rb_ary_push(queue->items, value);
  return self;
}

VALUE Gyro_Queue_shift(VALUE self) {
  Gyro_Queue_t *queue;
  GetGyro_Queue(self, queue);

  if (RARRAY_LEN(queue->items) == 0) {
    VALUE ret;
    VALUE watcher = Fiber_auto_watcher(rb_fiber_current());
    rb_ary_push(queue->shift_waiters, watcher);
    ret = rb_funcall(watcher, rb_intern("await_no_raise"), 0);
    // ret = Gyro_Async_await_no_raise(watcher);
    if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
      rb_ary_delete(queue->shift_waiters, watcher);
      return rb_funcall(rb_mKernel, ID_raise, 1, ret);
    }
    RB_GC_GUARD(ret);
  }

  return rb_ary_shift(queue->items);
}

VALUE Gyro_Queue_shift_no_wait(VALUE self) {
  Gyro_Queue_t *queue;
  GetGyro_Queue(self, queue);

  return rb_ary_shift(queue->items);
}

VALUE Gyro_Queue_shift_each(VALUE self) {
  Gyro_Queue_t *queue;
  VALUE old_queue;
  GetGyro_Queue(self, queue);
  old_queue = queue->items;
  queue->items = rb_ary_new();

  if (rb_block_given_p()) {
    long len = RARRAY_LEN(old_queue);
    long i;
    for (i = 0; i < len; i++) {
      rb_yield(RARRAY_AREF(old_queue, i));
    }
    RB_GC_GUARD(old_queue);
    return self;
  }
  else {
    RB_GC_GUARD(old_queue);
    return old_queue;
  }
}

VALUE Gyro_Queue_clear(VALUE self) {
  Gyro_Queue_t *queue;
  GetGyro_Queue(self, queue);

  rb_ary_clear(queue->items);
  return self;
}

VALUE Gyro_Queue_empty_p(VALUE self) {
  Gyro_Queue_t *queue;
  GetGyro_Queue(self, queue);

  return (RARRAY_LEN(queue->items) == 0) ? Qtrue : Qfalse;
}

void Init_Gyro_Queue() {
  cGyro_Queue = rb_define_class_under(mGyro, "Queue", rb_cData);
  rb_define_alloc_func(cGyro_Queue, Gyro_Queue_allocate);

  rb_define_method(cGyro_Queue, "initialize", Gyro_Queue_initialize, 0);
  rb_define_method(cGyro_Queue, "push", Gyro_Queue_push, 1);
  rb_define_method(cGyro_Queue, "<<", Gyro_Queue_push, 1);

  rb_define_method(cGyro_Queue, "pop", Gyro_Queue_shift, 0);
  rb_define_method(cGyro_Queue, "shift", Gyro_Queue_shift, 0);

  rb_define_method(cGyro_Queue, "shift_no_wait", Gyro_Queue_shift_no_wait, 0);

  rb_define_method(cGyro_Queue, "shift_each", Gyro_Queue_shift_each, 0);
  rb_define_method(cGyro_Queue, "clear", Gyro_Queue_clear, 0);
  rb_define_method(cGyro_Queue, "empty?", Gyro_Queue_empty_p, 0);
}


