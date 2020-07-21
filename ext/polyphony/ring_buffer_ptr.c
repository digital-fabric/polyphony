#include "polyphony.h"
#include "ring_buffer_ptr.h"

void ring_buffer_ptr_init(ring_buffer_ptr *buffer) {
  buffer->size = 1;
  buffer->count = 0;
  buffer->entries = malloc(buffer->size * sizeof(void *));
  buffer->head = 0;
  buffer->tail = 0;
}

void ring_buffer_ptr_free(ring_buffer_ptr *buffer) {
  free(buffer->entries);
}

int ring_buffer_ptr_empty_p(ring_buffer_ptr *buffer) {
  return buffer->count == 0;
}

void *ring_buffer_ptr_shift(ring_buffer_ptr *buffer) {
  void *ptr;
  if (buffer->count == 0) return 0;

  ptr = buffer->entries[buffer->head];
  buffer->head = (buffer->head + 1) % buffer->size;
  buffer->count--;
  return ptr;
}

void ring_buffer_ptr_resize(ring_buffer_ptr *buffer) {
  unsigned int old_size = buffer->size;
  buffer->size = old_size == 1 ? 4 : old_size * 2;
  buffer->entries = realloc(buffer->entries, buffer->size * sizeof(VALUE));
  for (unsigned int idx = 0; idx < buffer->head && idx < buffer->tail; idx++)
    buffer->entries[old_size + idx] = buffer->entries[idx];
  buffer->tail = buffer->head + buffer->count;
}

void ring_buffer_ptr_unshift(ring_buffer_ptr *buffer, void *ptr) {
  if (buffer->count == buffer->size) ring_buffer_ptr_resize(buffer);

  buffer->head = (buffer->head - 1) % buffer->size;
  buffer->entries[buffer->head] = ptr;
  buffer->count++;
}

void ring_buffer_ptr_push(ring_buffer_ptr *buffer, void *ptr) {
  if (buffer->count == buffer->size) ring_buffer_ptr_resize(buffer);

  buffer->entries[buffer->tail] = ptr;
  buffer->tail = (buffer->tail + 1) % buffer->size;
  buffer->count++;
}

void ring_buffer_ptr_delete_at(ring_buffer_ptr *buffer, unsigned int idx) {
  for (unsigned int idx2 = idx; idx2 != buffer->tail; idx2 = (idx2 + 1) % buffer->size) {
    buffer->entries[idx2] = buffer->entries[(idx2 + 1) % buffer->size];
  }
  buffer->count--;
  buffer->tail = (buffer->tail - 1) % buffer->size;
}

void ring_buffer_ptr_delete(ring_buffer_ptr *buffer, void *ptr) {
  for (unsigned int i = 0; i < buffer->count; i++) {
    unsigned int idx = (buffer->head + i) % buffer->size;
    if (buffer->entries[idx] == ptr) {
      ring_buffer_ptr_delete_at(buffer, idx);
      return;
    }
  }
}

void ring_buffer_ptr_clear(ring_buffer_ptr *buffer) {
  buffer->count = buffer->head = buffer->tail = 0;
}