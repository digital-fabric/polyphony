#include "polyphony.h"
#include "ring_buffer_value.h"

void ring_buffer_value_init(ring_buffer_value *buffer) {
  buffer->size = 1;
  buffer->count = 0;
  buffer->entries = malloc(buffer->size * sizeof(VALUE));
  buffer->head = 0;
  buffer->tail = 0;
}

void ring_buffer_value_free(ring_buffer_value *buffer) {
  free(buffer->entries);
}

int ring_buffer_value_empty_p(ring_buffer_value *buffer) {
  return buffer->count == 0;
}

VALUE ring_buffer_value_shift(ring_buffer_value *buffer) {
  VALUE value;
  if (buffer->count == 0) return Qnil;

  value = buffer->entries[buffer->head];
  buffer->head = (buffer->head + 1) % buffer->size;
  buffer->count--;
  // INSPECT(value);
  return value;
}

void ring_buffer_value_resize(ring_buffer_value *buffer) {
  unsigned int old_size = buffer->size;
  buffer->size = old_size == 1 ? 4 : old_size * 2;
  buffer->entries = realloc(buffer->entries, buffer->size * sizeof(VALUE));
  for (unsigned int idx = 0; idx < buffer->head && idx < buffer->tail; idx++)
    buffer->entries[old_size + idx] = buffer->entries[idx];
  buffer->tail = buffer->head + buffer->count;
}

void ring_buffer_value_unshift(ring_buffer_value *buffer, VALUE value) {
  if (buffer->count == buffer->size) ring_buffer_value_resize(buffer);

  buffer->head = (buffer->head - 1) % buffer->size;
  buffer->entries[buffer->head] = value;
  buffer->count++;
}

void ring_buffer_value_push(ring_buffer_value *buffer, VALUE value) {
  if (buffer->count == buffer->size) ring_buffer_value_resize(buffer);

  buffer->entries[buffer->tail] = value;
  buffer->tail = (buffer->tail + 1) % buffer->size;
  buffer->count++;
}

void ring_buffer_value_mark(ring_buffer_value *buffer) {
  for (unsigned int i = 0; i < buffer->count; i++)
    rb_gc_mark(buffer->entries[(buffer->head + i) % buffer->size]);
}

void ring_buffer_value_shift_each(ring_buffer_value *buffer) {
  for (unsigned int i = 0; i < buffer->count; i++)
    rb_yield(buffer->entries[(buffer->head + i) % buffer->size]);

  buffer->count = buffer->head = buffer->tail = 0;
}

VALUE ring_buffer_value_shift_all(ring_buffer_value *buffer) {
  VALUE array = rb_ary_new_capa(buffer->count);
  for (unsigned int i = 0; i < buffer->count; i++)
    rb_ary_push(array, buffer->entries[(buffer->head + i) % buffer->size]);
  buffer->count = buffer->head = buffer->tail = 0;
  return array;
}

void ring_buffer_value_delete_at(ring_buffer_value *buffer, unsigned int idx) {
  for (unsigned int idx2 = idx; idx2 != buffer->tail; idx2 = (idx2 + 1) % buffer->size) {
    buffer->entries[idx2] = buffer->entries[(idx2 + 1) % buffer->size];
  }
  buffer->count--;
  buffer->tail = (buffer->tail - 1) % buffer->size;
}

void ring_buffer_value_delete(ring_buffer_value *buffer, VALUE value) {
  for (unsigned int i = 0; i < buffer->count; i++) {
    unsigned int idx = (buffer->head + i) % buffer->size;
    if (buffer->entries[idx] == value) {
      ring_buffer_value_delete_at(buffer, idx);
      return;
    }
  }
}

void ring_buffer_value_clear(ring_buffer_value *buffer) {
  buffer->count = buffer->head = buffer->tail = 0;
}