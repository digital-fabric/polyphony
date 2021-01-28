#include "polyphony.h"
#include "runqueue_ring_buffer.h"

void runqueue_ring_buffer_init(runqueue_ring_buffer *buffer) {
  buffer->size = 1;
  buffer->count = 0;
  buffer->entries = malloc(buffer->size * sizeof(runqueue_entry));
  buffer->head = 0;
  buffer->tail = 0;
}

void runqueue_ring_buffer_free(runqueue_ring_buffer *buffer) {
  free(buffer->entries);
}

int runqueue_ring_buffer_empty_p(runqueue_ring_buffer *buffer) {
  return buffer->count == 0;
}

static runqueue_entry nil_runqueue_entry = {(Qnil), (Qnil)};

runqueue_entry runqueue_ring_buffer_shift(runqueue_ring_buffer *buffer) {
  if (buffer->count == 0) return nil_runqueue_entry;

  runqueue_entry value = buffer->entries[buffer->head];
  buffer->head = (buffer->head + 1) % buffer->size;
  buffer->count--;
  return value;
}

void runqueue_ring_buffer_resize(runqueue_ring_buffer *buffer) {
  unsigned int old_size = buffer->size;
  buffer->size = old_size == 1 ? 4 : old_size * 2;
  buffer->entries = realloc(buffer->entries, buffer->size * sizeof(runqueue_entry));
  for (unsigned int idx = 0; idx < buffer->head && idx < buffer->tail; idx++)
    buffer->entries[old_size + idx] = buffer->entries[idx];
  buffer->tail = buffer->head + buffer->count;
}

void runqueue_ring_buffer_unshift(runqueue_ring_buffer *buffer, VALUE fiber, VALUE value) {
  if (buffer->count == buffer->size) runqueue_ring_buffer_resize(buffer);

  buffer->head = (buffer->head - 1) % buffer->size;
  buffer->entries[buffer->head].fiber = fiber;
  buffer->entries[buffer->head].value = value;
  buffer->count++;
}

void runqueue_ring_buffer_push(runqueue_ring_buffer *buffer, VALUE fiber, VALUE value) {
  if (buffer->count == buffer->size) runqueue_ring_buffer_resize(buffer);

  buffer->entries[buffer->tail].fiber = fiber;
  buffer->entries[buffer->tail].value = value;
  buffer->tail = (buffer->tail + 1) % buffer->size;
  buffer->count++;
}

void runqueue_ring_buffer_mark(runqueue_ring_buffer *buffer) {
  for (unsigned int i = 0; i < buffer->count; i++) {
    rb_gc_mark(buffer->entries[(buffer->head + i) % buffer->size].fiber);
    rb_gc_mark(buffer->entries[(buffer->head + i) % buffer->size].value);
  }
}

void runqueue_ring_buffer_delete_at(runqueue_ring_buffer *buffer, unsigned int idx) {
  for (unsigned int idx2 = idx; idx2 != buffer->tail; idx2 = (idx2 + 1) % buffer->size) {
    buffer->entries[idx2] = buffer->entries[(idx2 + 1) % buffer->size];
  }
  buffer->count--;
  buffer->tail = (buffer->tail - 1) % buffer->size;
}

void runqueue_ring_buffer_delete(runqueue_ring_buffer *buffer, VALUE fiber) {
  for (unsigned int i = 0; i < buffer->count; i++) {
    unsigned int idx = (buffer->head + i) % buffer->size;
    if (buffer->entries[idx].fiber == fiber) {
      runqueue_ring_buffer_delete_at(buffer, idx);
      return;
    }
  }
}

int runqueue_ring_buffer_index_of(runqueue_ring_buffer *buffer, VALUE fiber) {
  for (unsigned int i = 0; i < buffer->count; i++) {
    unsigned int idx = (buffer->head + i) % buffer->size;
    if (buffer->entries[idx].fiber == fiber)
      return i;
  }
  return -1;
}

void runqueue_ring_buffer_clear(runqueue_ring_buffer *buffer) {
  buffer->count = buffer->head = buffer->tail = 0;
}