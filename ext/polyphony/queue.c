#include "polyphony.h"
#include "ring_buffer.h"

typedef struct queue {
  ring_buffer values;
  ring_buffer shift_queue;
  ring_buffer push_queue;
  unsigned int capacity;
} Queue_t;

VALUE cQueue = Qnil;

static void Queue_mark(void *ptr) {
  Queue_t *queue = ptr;
  ring_buffer_mark(&queue->values);
  ring_buffer_mark(&queue->shift_queue);
  ring_buffer_mark(&queue->push_queue);
}

static void Queue_free(void *ptr) {
  Queue_t *queue = ptr;
  ring_buffer_free(&queue->values);
  ring_buffer_free(&queue->shift_queue);
  ring_buffer_free(&queue->push_queue);
  xfree(ptr);
}

static size_t Queue_size(const void *ptr) {
  return sizeof(Queue_t);
}

static const rb_data_type_t Queue_type = {
  "Queue",
  {Queue_mark, Queue_free, Queue_size,},
  0, 0, 0
};

static VALUE Queue_allocate(VALUE klass) {
  Queue_t *queue;

  queue = ALLOC(Queue_t);
  return TypedData_Wrap_Struct(klass, &Queue_type, queue);
}

#define GetQueue(obj, queue) \
  TypedData_Get_Struct((obj), Queue_t, &Queue_type, (queue))

static VALUE Queue_initialize(int argc, VALUE *argv, VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_init(&queue->values);
  ring_buffer_init(&queue->shift_queue);
  ring_buffer_init(&queue->push_queue);
  queue->capacity = (argc == 1) ?  NUM2UINT(argv[0]) : 0;

  return self;
}

inline void queue_schedule_first_blocked_fiber(ring_buffer *queue) {
  if (queue->count) {
    VALUE fiber = ring_buffer_shift(queue);
    if (fiber != Qnil) Fiber_make_runnable(fiber, Qnil);
  }
}

inline void queue_schedule_all_blocked_fibers(ring_buffer *queue) {
  while (queue->count) {
    VALUE fiber = ring_buffer_shift(queue);
    if (fiber != Qnil) Fiber_make_runnable(fiber, Qnil);
  }
}

inline void queue_schedule_blocked_fibers_to_capacity(Queue_t *queue) {
  for (unsigned int i = queue->values.count; (i < queue->capacity) && queue->push_queue.count; i++) {
    VALUE fiber = ring_buffer_shift(&queue->push_queue);
    if (fiber != Qnil) Fiber_make_runnable(fiber, Qnil);
  }
}

static inline void capped_queue_block_push(Queue_t *queue) {
  VALUE fiber = rb_fiber_current();
  VALUE backend = rb_ivar_get(rb_thread_current(), ID_ivar_backend);
  VALUE switchpoint_result;
  while (1) {
    if (queue->capacity > queue->values.count) Fiber_make_runnable(fiber, Qnil);

    ring_buffer_push(&queue->push_queue, fiber);
    switchpoint_result = Backend_wait_event(backend, Qnil);
    ring_buffer_delete(&queue->push_queue, fiber);

    RAISE_IF_EXCEPTION(switchpoint_result);
    RB_GC_GUARD(switchpoint_result);
    if (queue->capacity > queue->values.count) break;
  }
}

VALUE Queue_push(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (queue->capacity) capped_queue_block_push(queue);

  queue_schedule_first_blocked_fiber(&queue->shift_queue);
  ring_buffer_push(&queue->values, value);

  return self;
}

VALUE Queue_unshift(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (queue->capacity) capped_queue_block_push(queue);

  queue_schedule_first_blocked_fiber(&queue->shift_queue);
  ring_buffer_unshift(&queue->values, value);

  return self;
}

VALUE Queue_shift(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  VALUE fiber = rb_fiber_current();
  VALUE thread = rb_thread_current();
  VALUE backend = rb_ivar_get(thread, ID_ivar_backend);

  while (1) {
    if (queue->values.count) Fiber_make_runnable(fiber, Qnil);

    ring_buffer_push(&queue->shift_queue, fiber);
    VALUE switchpoint_result = Backend_wait_event(backend, Qnil);
    ring_buffer_delete(&queue->shift_queue, fiber);

    RAISE_IF_EXCEPTION(switchpoint_result);
    RB_GC_GUARD(switchpoint_result);
    if (queue->values.count) break;
  }
  VALUE value = ring_buffer_shift(&queue->values);
  if ((queue->capacity) && (queue->capacity > queue->values.count))
    queue_schedule_first_blocked_fiber(&queue->push_queue);
  RB_GC_GUARD(value);
  return value;
}

VALUE Queue_delete(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_delete(&queue->values, value);

  if (queue->capacity && (queue->capacity > queue->values.count))
    queue_schedule_first_blocked_fiber(&queue->push_queue);

  return self;
}

VALUE Queue_cap(VALUE self, VALUE cap) {
  unsigned int new_capacity = NUM2UINT(cap);
  Queue_t *queue;
  GetQueue(self, queue);
  queue->capacity = new_capacity;
  
  if (queue->capacity)
    queue_schedule_blocked_fibers_to_capacity(queue);
  else
    queue_schedule_all_blocked_fibers(&queue->push_queue);
  
  return self;
}

VALUE Queue_capped_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return queue->capacity ? UINT2NUM(queue->capacity) : Qnil;
}

VALUE Queue_clear(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_clear(&queue->values);
  if (queue->capacity) queue_schedule_blocked_fibers_to_capacity(queue);

  return self;
}

long Queue_len(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return queue->values.count;
}

VALUE Queue_shift_each(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_shift_each(&queue->values);
  if (queue->capacity) queue_schedule_blocked_fibers_to_capacity(queue);
  return self;
}

VALUE Queue_shift_all(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  VALUE result = ring_buffer_shift_all(&queue->values);
  if (queue->capacity) queue_schedule_blocked_fibers_to_capacity(queue);
  return result;
}

VALUE Queue_flush_waiters(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  while(1) {
    VALUE fiber = ring_buffer_shift(&queue->shift_queue);
    if (fiber == Qnil) return self;

    Fiber_make_runnable(fiber, value);
  }
}

VALUE Queue_empty_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (!queue->values.count) ? Qtrue : Qfalse;
}

VALUE Queue_pending_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (queue->shift_queue.count) ? Qtrue : Qfalse;
}

VALUE Queue_size_m(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return INT2NUM(queue->values.count);
}

void Init_Queue() {
  cQueue = rb_define_class_under(mPolyphony, "Queue", rb_cObject);
  rb_define_alloc_func(cQueue, Queue_allocate);

  rb_define_method(cQueue, "initialize", Queue_initialize, -1);
  rb_define_method(cQueue, "push", Queue_push, 1);
  rb_define_method(cQueue, "<<", Queue_push, 1);
  rb_define_method(cQueue, "unshift", Queue_unshift, 1);

  rb_define_method(cQueue, "shift", Queue_shift, 0);
  rb_define_method(cQueue, "pop", Queue_shift, 0);
  rb_define_method(cQueue, "delete", Queue_delete, 1);
  rb_define_method(cQueue, "clear", Queue_clear, 0);

  rb_define_method(cQueue, "cap", Queue_cap, 1);
  rb_define_method(cQueue, "capped?", Queue_capped_p, 0);

  rb_define_method(cQueue, "shift_each", Queue_shift_each, 0);
  rb_define_method(cQueue, "shift_all", Queue_shift_all, 0);
  rb_define_method(cQueue, "flush_waiters", Queue_flush_waiters, 1);
  rb_define_method(cQueue, "empty?", Queue_empty_p, 0);
  rb_define_method(cQueue, "pending?", Queue_pending_p, 0);
  rb_define_method(cQueue, "size", Queue_size_m, 0);
}
