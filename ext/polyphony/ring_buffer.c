#include "polyphony.h"
#include "ring_buffer.h"

void ring_buffer_init(ring_buffer *buffer) {
  buffer->size = 1;
  buffer->count = 0;
  buffer->entries = malloc(buffer->size * sizeof(VALUE));
  buffer->head = 0;
  buffer->tail = 0;
}

void ring_buffer_free(ring_buffer *buffer) {
  free(buffer->entries);
}

int ring_buffer_empty_p(ring_buffer *buffer) {
  return buffer->count == 0;
}

#define TRACE_RING_BUFFER(func, buffer) printf( \
  "%s size: %d count: %d head: %d tail: %d\n", \
  func, \
  buffer->size, \
  buffer->count, \
  buffer->head, \
  buffer->tail \
)

VALUE ring_buffer_shift(ring_buffer *buffer) {
  // TRACE_RING_BUFFER("ring_buffer_shift", buffer);

  VALUE value;
  if (buffer->count == 0) return Qnil;

  value = buffer->entries[buffer->head];
  buffer->head = (buffer->head + 1) % buffer->size;
  buffer->count--;
  // INSPECT(value);
  return value;
}

void ring_buffer_resize(ring_buffer *buffer) {
  // TRACE_RING_BUFFER("ring_buffer_resize", buffer);

  unsigned int old_size = buffer->size;
  buffer->size = old_size == 1 ? 4 : old_size * 2;
  // printf("new size: %d\n", buffer->size);
  buffer->entries = realloc(buffer->entries, buffer->size * sizeof(VALUE));
  for (unsigned int idx = 0; idx < buffer->head && idx < buffer->tail; idx++)
    buffer->entries[old_size + idx] = buffer->entries[idx];
  buffer->tail = buffer->head + buffer->count;
}

void ring_buffer_unshift(ring_buffer *buffer, VALUE value) {
  // TRACE_RING_BUFFER("ring_buffer_unshift", buffer);
  // INSPECT(value);

  if (buffer->count == buffer->size) ring_buffer_resize(buffer);

  buffer->head = (buffer->head - 1) % buffer->size;
  buffer->entries[buffer->head] = value;
  buffer->count++;
}

void ring_buffer_push(ring_buffer *buffer, VALUE value) {
  // TRACE_RING_BUFFER("ring_buffer_push", buffer);
  // INSPECT(value);
  if (buffer->count == buffer->size) ring_buffer_resize(buffer);

  buffer->entries[buffer->tail] = value;
  buffer->tail = (buffer->tail + 1) % buffer->size;
  buffer->count++;
}

void ring_buffer_mark(ring_buffer *buffer) {
  for (unsigned int i = 0; i < buffer->count; i++)
    rb_gc_mark(buffer->entries[(buffer->head + i) % buffer->size]);
}

void ring_buffer_shift_each(ring_buffer *buffer) {
  // TRACE_RING_BUFFER("ring_buffer_shift_each", buffer);

  for (unsigned int i = 0; i < buffer->count; i++)
    rb_yield(buffer->entries[(buffer->head + i) % buffer->size]);

  buffer->count = buffer->head = buffer->tail = 0;
}

VALUE ring_buffer_shift_all(ring_buffer *buffer) {
  // TRACE_RING_BUFFER("ring_buffer_all", buffer);
  VALUE array = rb_ary_new_capa(buffer->count);
  for (unsigned int i = 0; i < buffer->count; i++)
    rb_ary_push(array, buffer->entries[(buffer->head + i) % buffer->size]);
  buffer->count = buffer->head = buffer->tail = 0;
  return array;
}

void ring_buffer_delete_at(ring_buffer *buffer, unsigned int idx) {
  for (unsigned int idx2 = idx; idx2 != buffer->tail; idx2 = (idx2 + 1) % buffer->size) {
    buffer->entries[idx2] = buffer->entries[(idx2 + 1) % buffer->size];
  }
  buffer->count--;
  buffer->tail = (buffer->tail - 1) % buffer->size;
}

void ring_buffer_delete(ring_buffer *buffer, VALUE value) {
  // TRACE_RING_BUFFER("ring_buffer_delete", buffer);
  for (unsigned int i = 0; i < buffer->count; i++) {
    unsigned int idx = (buffer->head + i) % buffer->size;
    if (buffer->entries[idx] == value) {
      ring_buffer_delete_at(buffer, idx);
      return;
    }
  }
}

void ring_buffer_clear(ring_buffer *buffer) {
  // TRACE_RING_BUFFER("ring_buffer_clear", buffer);
  buffer->count = buffer->head = buffer->tail = 0;
}