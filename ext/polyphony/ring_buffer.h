#ifndef RING_BUFFER_H
#define RING_BUFFER_H

#include "ruby.h"

typedef struct ring_buffer {
  VALUE *entries;
  unsigned int size;
  unsigned int count;
  unsigned int head;
  unsigned int tail;
} ring_buffer;

void ring_buffer_init(ring_buffer *buffer);
void ring_buffer_free(ring_buffer *buffer);
void ring_buffer_mark(ring_buffer *buffer);
int ring_buffer_empty_p(ring_buffer *buffer);
void ring_buffer_clear(ring_buffer *buffer);

VALUE ring_buffer_shift(ring_buffer *buffer);
void ring_buffer_unshift(ring_buffer *buffer, VALUE value);
void ring_buffer_push(ring_buffer *buffer, VALUE value);

void ring_buffer_shift_each(ring_buffer *buffer);
VALUE ring_buffer_shift_all(ring_buffer *buffer);
void ring_buffer_delete(ring_buffer *buffer, VALUE value);

#endif /* RING_BUFFER_H */
