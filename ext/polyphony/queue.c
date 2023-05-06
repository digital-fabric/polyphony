#include "polyphony.h"
#include "ring_buffer.h"

/*
 * Document-class: Polyphony::Queue
 *
 * This class implements a FIFO queue that can be used to exchange data between
 * different fibers or threads. The queue can simultaneously service multiple
 * producers and multiple consumers. A consumers trying to remove an item from
 * an empty queue will block at least one item is added to the queue.
 *
 * A queue can also be capped in order to limit its depth. A producer trying to
 * add an item to a full capped queue will block until at least one item is
 * removed from it.
 */

typedef struct queue {
  unsigned int closed;
  ring_buffer values;
  ring_buffer shift_queue;
  ring_buffer push_queue;
  unsigned int capacity;
} Queue_t;

VALUE cQueue = Qnil;
VALUE cClosedQueueError = Qnil;
VALUE cThreadError = Qnil;

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

/* call-seq:
 *   Queue.new -> queue
 *   Queue.new(capacity) -> queue
 *
 * Initializes a queue instance. If the capacity is given, the queue becomes
 * capped, i.e. it cannot contain more elements than its capacity. When trying
 * to add items to a capped queue that is full, the current fiber will block
 * until at least one item is removed from the queue.
 * 
 * @return [void]
 */

static VALUE Queue_initialize(int argc, VALUE *argv, VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  queue->closed = 0;
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

/* call-seq:
 *   queue.push(value) -> queue
 *   queue.enq(value) -> queue
 *   queue << value -> queue
 *
 * Adds the given value to the queue's end. If the queue is capped and full, the
 * call will block until a value is removed from the queue.
 * 
 * @param value [any] value to be added to the queue
 * @return [Queue] self
 */

VALUE Queue_push(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (queue->closed)
    rb_raise(cClosedQueueError, "queue closed");

  if (queue->capacity) capped_queue_block_push(queue);

  queue_schedule_first_blocked_fiber(&queue->shift_queue);
  ring_buffer_push(&queue->values, value);

  return self;
}

/* call-seq:
 *   queue.unshift(value) -> queue
 *
 * Adds the given value to the queue's beginning. If the queue is capped and
 * full, the call will block until a value is removed from the queue.
 * 
 * @param value [any] value to be added to the queue
 * @return [Queue] self
 */

VALUE Queue_unshift(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (queue->closed)
    rb_raise(cClosedQueueError, "queue closed");

  if (queue->capacity) capped_queue_block_push(queue);

  queue_schedule_first_blocked_fiber(&queue->shift_queue);
  ring_buffer_unshift(&queue->values, value);

  return self;
}

VALUE Queue_shift_nonblock(Queue_t *queue) {
  if (queue->values.count) {
    VALUE value = ring_buffer_shift(&queue->values);
    if ((queue->capacity) && (queue->capacity > queue->values.count))
      queue_schedule_first_blocked_fiber(&queue->push_queue);
    RB_GC_GUARD(value);
    return value;
  }
  rb_raise(cThreadError, "queue empty");
}

VALUE Queue_shift_block(Queue_t *queue) {
  VALUE fiber = rb_fiber_current();
  VALUE thread = rb_thread_current();
  VALUE backend = rb_ivar_get(thread, ID_ivar_backend);
  VALUE value;

  if (queue->closed && !queue->values.count)
    rb_raise(cClosedQueueError, "queue closed");

  while (1) {
    VALUE switchpoint_result;

    if (queue->values.count) Fiber_make_runnable(fiber, Qnil);

    ring_buffer_push(&queue->shift_queue, fiber);
    switchpoint_result = Backend_wait_event(backend, Qnil);
    ring_buffer_delete(&queue->shift_queue, fiber);

    RAISE_IF_EXCEPTION(switchpoint_result);
    RB_GC_GUARD(switchpoint_result);
    if (queue->values.count) break;
    if (queue->closed) return Qnil;
  }
  value = ring_buffer_shift(&queue->values);
  if ((queue->capacity) && (queue->capacity > queue->values.count))
    queue_schedule_first_blocked_fiber(&queue->push_queue);
  RB_GC_GUARD(value);
  return value;
}

/* call-seq:
 *   queue.shift -> value
 *   queue.shift(true) -> value
 *   queue.pop -> value
 *   queue.pop(true) -> value
 *   queue.deq -> value
 *   queue.deq(true) -> value
 *
 * Removes the first value in the queue and returns it. If the optional nonblock
 * parameter is true, the operation is non-blocking. In non-blocking mode, if
 * the queue is empty, a ThreadError exception is raised. In blocking mode, if
 * the queue is empty, the call will block until an item is added to the queue.
 *
 * @return [any] first value in queue
 */

VALUE Queue_shift(int argc,VALUE *argv, VALUE self) {
  int nonblock = argc && RTEST(argv[0]);
  Queue_t *queue;
  GetQueue(self, queue);

  return nonblock ?
    Queue_shift_nonblock(queue) :
    Queue_shift_block(queue);
}

/* call-seq:
 *   queue.delete(value) -> queue
 *
 * Removes the given value from the queue.
 *
 * @return [Queue] self
 */

VALUE Queue_delete(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_delete(&queue->values, value);

  if (queue->capacity && (queue->capacity > queue->values.count))
    queue_schedule_first_blocked_fiber(&queue->push_queue);

  return self;
}

/* call-seq:
 *   queue.cap(capacity) -> queue
 *
 * Sets the capacity for the queue to the given value. If 0 or nil is given, the
 * queue becomes uncapped.
 *
 * @param cap [Integer, nil] new capacity
 * @return [Queue] self
 */

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

/* call-seq:
 *   queue.capped? -> bool
 *
 * Returns true if the queue is capped.
 *
 * @return [boolean] is the queue capped
 */

VALUE Queue_capped_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return queue->capacity ? INT2FIX(queue->capacity) : Qnil;
}

/* call-seq:
 *   queue.clear -> queue
 *
 * Removes all values from the queue.
 *
 * @return [Queue] self
 */

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

/* call-seq:
 *   queue.shift_each { |value| do_something(value) } -> queue
 *
 * Iterates over all values in the queue, removing each item and passing it to
 * the given block.
 *
 * @yield [any] value passed to the given block
 * @return [Queue] self
 */

VALUE Queue_shift_each(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  ring_buffer_shift_each(&queue->values);
  if (queue->capacity) queue_schedule_blocked_fibers_to_capacity(queue);
  return self;
}

/* call-seq:
 *   queue.shift_all -> array
 *
 * Returns all values currently in the queue, clearing the queue.
 *
 * @return [Array] all values
 */

VALUE Queue_shift_all(VALUE self) {
  Queue_t *queue;
  VALUE result;

  GetQueue(self, queue);

  result = ring_buffer_shift_all(&queue->values);
  if (queue->capacity) queue_schedule_blocked_fibers_to_capacity(queue);
  return result;
}

/* call-seq:
 *   queue.flush_waiters -> queue
 *
 * Flushes all fibers currently blocked waiting to remove items from the queue,
 * resuming them with the given value.
 *
 * @param value [any] value to resome all waiting fibers with
 * @return [Queue] self
 */

VALUE Queue_flush_waiters(VALUE self, VALUE value) {
  Queue_t *queue;
  GetQueue(self, queue);

  while(1) {
    VALUE fiber = ring_buffer_shift(&queue->shift_queue);
    if (fiber == Qnil) return self;

    Fiber_make_runnable(fiber, value);
  }

  return self;
}

/* call-seq:
 *   queue.empty? -> bool
 *
 * Returns true if the queue is empty.
 *
 * @return [boolean]
 */

VALUE Queue_empty_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (!queue->values.count) ? Qtrue : Qfalse;
}

/* call-seq:
 *   queue.pending? -> bool
 *
 * Returns true if any fibers are currently waiting to remove items from the
 * queue.
 *
 * @return [boolean]
 */

VALUE Queue_pending_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (queue->shift_queue.count) ? Qtrue : Qfalse;
}

/* call-seq:
 *   queue.num_waiting -> integer
 *
 * Returns the number of fibers currently waiting to remove items from the
 * queue.
 *
 * @return [Integer]
 */

VALUE Queue_num_waiting(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return INT2FIX(queue->shift_queue.count);
}

/* call-seq:
 *   queue.size -> integer
 *   queue.length -> integer 
 *
 * Returns the number of values currently in the queue.
 *
 * @return [Integer] number of values in the queue
 */

VALUE Queue_size_m(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return INT2FIX(queue->values.count);
}

/* call-seq:
 *   queue.closed? -> bool
 *
 * Returns true if the queue has been closed.
 *
 * @return [boolean]
 */

VALUE Queue_closed_p(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  return (queue->closed) ? Qtrue : Qfalse;
}

/* call-seq:
 *   queue.close -> queue
 *
 * Marks the queue as closed. Any fibers currently waiting on the queue are
 * resumed with a `nil` value. After the queue is closed, trying to remove items
 * from the queue will cause a `ClosedQueueError` to be raised.
 *
 * @return [Queue] self
 */

VALUE Queue_close(VALUE self) {
  Queue_t *queue;
  GetQueue(self, queue);

  if (queue->closed) goto end;
  queue->closed = 1;

  // release all fibers waiting on `#shift`
  while (queue->shift_queue.count) {
    VALUE fiber = ring_buffer_shift(&queue->shift_queue);
    if (fiber == Qnil) break;
    Fiber_make_runnable(fiber, Qnil);
  }

end:
  return self;
}

void Init_Queue(void) {
  cClosedQueueError = rb_const_get(rb_cObject, rb_intern("ClosedQueueError"));
  cThreadError = rb_const_get(rb_cObject, rb_intern("ThreadError"));

  /* Queue implements a FIFO queue. */
  cQueue = rb_define_class_under(mPolyphony, "Queue", rb_cObject);
  rb_define_alloc_func(cQueue, Queue_allocate);

  rb_define_method(cQueue, "initialize", Queue_initialize, -1);
  rb_define_method(cQueue, "push", Queue_push, 1);
  rb_define_method(cQueue, "<<", Queue_push, 1);
  rb_define_method(cQueue, "enq", Queue_push, 1);
  rb_define_method(cQueue, "unshift", Queue_unshift, 1);

  rb_define_method(cQueue, "shift", Queue_shift, -1);
  rb_define_method(cQueue, "pop", Queue_shift, -1);
  rb_define_method(cQueue, "deq", Queue_shift, -1);

  rb_define_method(cQueue, "delete", Queue_delete, 1);
  rb_define_method(cQueue, "clear", Queue_clear, 0);

  rb_define_method(cQueue, "size", Queue_size_m, 0);
  rb_define_method(cQueue, "length", Queue_size_m, 0);

  rb_define_method(cQueue, "cap", Queue_cap, 1);
  rb_define_method(cQueue, "capped?", Queue_capped_p, 0);

  rb_define_method(cQueue, "shift_each", Queue_shift_each, 0);
  rb_define_method(cQueue, "shift_all", Queue_shift_all, 0);
  rb_define_method(cQueue, "flush_waiters", Queue_flush_waiters, 1);
  rb_define_method(cQueue, "empty?", Queue_empty_p, 0);
  rb_define_method(cQueue, "pending?", Queue_pending_p, 0);
  rb_define_method(cQueue, "num_waiting", Queue_num_waiting, 0);

  rb_define_method(cQueue, "closed?", Queue_closed_p, 0);
  rb_define_method(cQueue, "close", Queue_close, 0);
}
