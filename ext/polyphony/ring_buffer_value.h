#ifndef RING_BUFFER_VALUE_H
#define RING_BUFFER_VALUE_H

#include "ruby.h"

typedef struct ring_buffer_value {
  VALUE *entries;
  unsigned int size;
  unsigned int count;
  unsigned int head;
  unsigned int tail;
} ring_buffer_value;

void ring_buffer_value_init(ring_buffer_value *buffer);
void ring_buffer_value_free(ring_buffer_value *buffer);
void ring_buffer_value_mark(ring_buffer_value *buffer);
int ring_buffer_value_empty_p(ring_buffer_value *buffer);
void ring_buffer_value_clear(ring_buffer_value *buffer);

VALUE ring_buffer_value_shift(ring_buffer_value *buffer);
void ring_buffer_value_unshift(ring_buffer_value *buffer, VALUE value);
void ring_buffer_value_push(ring_buffer_value *buffer, VALUE value);

void ring_buffer_value_shift_each(ring_buffer_value *buffer);
VALUE ring_buffer_value_shift_all(ring_buffer_value *buffer);
void ring_buffer_value_delete(ring_buffer_value *buffer, VALUE value);

#endif /* RING_BUFFER_VALUE_H */