#include "polyphony.h"
#include "runqueue_ring_buffer.h"

typedef struct queue {
  runqueue_ring_buffer entries;
  unsigned int high_watermark;
  unsigned int switch_count;
} Runqueue_t;

VALUE cRunqueue = Qnil;

static void Runqueue_mark(void *ptr) {
  Runqueue_t *runqueue = ptr;
  runqueue_ring_buffer_mark(&runqueue->entries);
}

static void Runqueue_free(void *ptr) {
  Runqueue_t *runqueue = ptr;
  runqueue_ring_buffer_free(&runqueue->entries);
  xfree(ptr);
}

static size_t Runqueue_size(const void *ptr) {
  return sizeof(Runqueue_t);
}

static const rb_data_type_t Runqueue_type = {
  "Runqueue",
  {Runqueue_mark, Runqueue_free, Runqueue_size,},
  0, 0, 0
};

static VALUE Runqueue_allocate(VALUE klass) {
  Runqueue_t *runqueue;

  runqueue = ALLOC(Runqueue_t);
  return TypedData_Wrap_Struct(klass, &Runqueue_type, runqueue);
}

#define GetRunqueue(obj, runqueue) \
  TypedData_Get_Struct((obj), Runqueue_t, &Runqueue_type, (runqueue))

static VALUE Runqueue_initialize(VALUE self) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);

  runqueue_ring_buffer_init(&runqueue->entries);
  runqueue->high_watermark = 0;
  runqueue->switch_count = 0;

  return self;
}

void Runqueue_push(VALUE self, VALUE fiber, VALUE value, int reschedule) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);

  if (reschedule) runqueue_ring_buffer_delete(&runqueue->entries, fiber);
  runqueue_ring_buffer_push(&runqueue->entries, fiber, value);
  if (runqueue->entries.count > runqueue->high_watermark)
    runqueue->high_watermark = runqueue->entries.count;
}

void Runqueue_unshift(VALUE self, VALUE fiber, VALUE value, int reschedule) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);
  if (reschedule) runqueue_ring_buffer_delete(&runqueue->entries, fiber);
  runqueue_ring_buffer_unshift(&runqueue->entries, fiber, value);
  if (runqueue->entries.count > runqueue->high_watermark)
    runqueue->high_watermark = runqueue->entries.count;
}

runqueue_entry Runqueue_shift(VALUE self) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);
  runqueue_entry entry = runqueue_ring_buffer_shift(&runqueue->entries);
  if (entry.fiber == Qnil)
    runqueue->high_watermark = 0;
  else
    runqueue->switch_count += 1;
  return entry;
}

void Runqueue_delete(VALUE self, VALUE fiber) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);
  runqueue_ring_buffer_delete(&runqueue->entries, fiber);
}

int Runqueue_index_of(VALUE self, VALUE fiber) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);
  return runqueue_ring_buffer_index_of(&runqueue->entries, fiber);
}

void Runqueue_clear(VALUE self) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);
  runqueue_ring_buffer_clear(&runqueue->entries);
}

long Runqueue_len(VALUE self) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);

  return runqueue->entries.count;
}

int Runqueue_empty_p(VALUE self) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);

  return (runqueue->entries.count == 0);
}

static const unsigned int ANTI_STARVE_HIGH_WATERMARK_THRESHOLD = 128;
static const unsigned int ANTI_STARVE_SWITCH_COUNT_THRESHOLD = 64;

int Runqueue_should_poll_nonblocking(VALUE self) {
  Runqueue_t *runqueue;
  GetRunqueue(self, runqueue);

  if (runqueue->high_watermark < ANTI_STARVE_HIGH_WATERMARK_THRESHOLD) return 0;
  if (runqueue->switch_count < ANTI_STARVE_SWITCH_COUNT_THRESHOLD) return 0;

  // the 
  runqueue->switch_count = 0;
  return 1;
}

void Init_Runqueue() {
  cRunqueue = rb_define_class_under(mPolyphony, "Runqueue", rb_cObject);
  rb_define_alloc_func(cRunqueue, Runqueue_allocate);

  rb_define_method(cRunqueue, "initialize", Runqueue_initialize, 0);
}
