#ifndef RING_BUFFER_PTR_H
#define RING_BUFFER_PTR_H

#include "ruby.h"

typedef struct ring_buffer_ptr {
  void **entries;
  unsigned int size;
  unsigned int count;
  unsigned int head;
  unsigned int tail;
} ring_buffer_ptr;

void ring_buffer_ptr_init(ring_buffer_ptr *buffer);
void ring_buffer_ptr_free(ring_buffer_ptr *buffer);
int ring_buffer_ptr_empty_p(ring_buffer_ptr *buffer);
void ring_buffer_ptr_clear(ring_buffer_ptr *buffer);

void *ring_buffer_ptr_shift(ring_buffer_ptr *buffer);
void ring_buffer_ptr_unshift(ring_buffer_ptr *buffer, void *ptr);
void ring_buffer_ptr_push(ring_buffer_ptr *buffer, void *ptr);

void ring_buffer_ptr_delete(ring_buffer_ptr *buffer, void *ptr);

#endif /* RING_BUFFER_PTR_H */