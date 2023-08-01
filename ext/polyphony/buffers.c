#include <stdlib.h>
#include <errno.h>
#include "buffers.h"

static buffer_manager bm;

inline int power_of_two(int x)
{
  int p = 1;
  while(x > (1 << p)) p++;
  return p;
}

inline int normalized_power_of_two(size_t len)
{
  int power = power_of_two(len);
  if (power < FREE_LIST_MIN_POWER_OF_TWO)
    power = FREE_LIST_MIN_POWER_OF_TWO;

  return (power > FREE_LIST_MAX_POWER_OF_TWO) ? -1 : power;
}

void bm_unshift(int free_list_idx, buffer_descriptor *desc)
{
  buffer_descriptor *head = bm.free_lists[free_list_idx];
  desc->next = head;
  if (head) head->prev = desc;
  bm.free_lists[free_list_idx] = desc;
}

void bm_shift(int free_list_idx, buffer_descriptor **desc)
{
  (*desc) = bm.free_lists[free_list_idx];
  bm.free_lists[free_list_idx] = (*desc) ? (*desc)->next : NULL;
  (*desc)->prev = NULL;
  (*desc)->next = NULL;
}

#define MULTI_ALLOC_THRESHOLD (1 << 20)

void bm_populate(int free_list_idx)
{
  size_t len = 1 << (FREE_LIST_MIN_POWER_OF_TWO + free_list_idx);
  int times = (len <= MULTI_ALLOC_THRESHOLD) ? 4 : 1;
  
  buffer_descriptor *base = malloc(sizeof(buffer_descriptor) * times);
  memset(base, 0, sizeof(buffer_descriptor) * times);

  char *buffer_base = malloc(len * times);

  for (int i = 0; i < times; i++) {
    buffer_descriptor *desc = base + i;
    desc->type = BT_MANAGED;
    desc->ptr = buffer_base + (len * i);
    desc->capacity = len;
    bm_unshift(free_list_idx, desc);
  }
}

int bm_prep_buffer_managed(buffer_descriptor **desc, size_t len)
{
  int power = normalized_power_of_two(len);
  if (power == -1) return -1;

  int idx = FREE_LIST_IDX(power);

  *desc = bm.free_lists[idx];
  if (!*desc) {
    bm_populate(idx);
    *desc = bm.free_lists[idx];
  }

  bm_shift(idx, desc);
  return 0;
}

int bm_prep_buffer_single_use(buffer_descriptor **desc, size_t len)
{
  (*desc) = malloc(sizeof(buffer_descriptor));
  (*desc)->type = BT_SINGLE_USE;
  (*desc)->ptr = malloc(len);
  (*desc)->len = 0;
  (*desc)->capacity = len;
  (*desc)->prev = NULL;
  (*desc)->next = NULL;
  return 0;
}

int bm_prep_buffer_string(buffer_descriptor **desc, size_t len)
{
  (*desc) = malloc(sizeof(buffer_descriptor));
  (*desc)->type = BT_STRING;
  (*desc)->str = rb_str_new_literal("");
  rb_str_resize((*desc)->str, len);
  (*desc)->ptr = RSTRING_PTR((*desc)->str);
  (*desc)->len = 0;
  (*desc)->capacity = rb_str_capacity((*desc)->str);
  (*desc)->prev = NULL;
  (*desc)->next = NULL;
  return 0;
}

inline int bm_prep_buffer(buffer_descriptor **desc, enum buffer_type type, size_t len)
{
  switch (type) {
  case BT_MANAGED:
    return bm_prep_buffer_managed(desc, len);
  case BT_SINGLE_USE:
    return bm_prep_buffer_single_use(desc, len);
  case BT_STRING:
    return bm_prep_buffer_string(desc, len);
  }
  return -1;
}

int bm_dispose_managed(buffer_descriptor *desc) {
  int power = normalized_power_of_two(desc->capacity);
  int idx = FREE_LIST_IDX(power);

  bm_unshift(idx, desc);
  return 0;
}

int bm_dispose_single_use(buffer_descriptor *desc) {
  free(desc->ptr);
  free(desc);
  return 0;
}

int bm_dispose_string(buffer_descriptor *desc) {
  free(desc);
  return 0;
}

int bm_dispose(buffer_descriptor *desc)
{
  switch (desc->type) {
  case BT_MANAGED:
    return bm_dispose_managed(desc);
  case BT_SINGLE_USE:
    return bm_dispose_single_use(desc);
  case BT_STRING:
    return bm_dispose_string(desc);
  }
  return -1;
}

void bm_trace(void)
{
  printf("**********************\n");
  for (int i = 0; i < FREE_LIST_COUNT; i++) {
    int count = 0;
    buffer_descriptor *desc = bm.free_lists[i];
    while (desc) {
      count++;
      desc = desc->next;
    }
    if (count > 0)
      printf("%d: %d\n", 1 << (FREE_LIST_MIN_POWER_OF_TWO + i), count);
  }
}

int bm_mark(void)
{
  for (int i = 0; i < FREE_LIST_COUNT; i++) {
    buffer_descriptor *desc = bm.free_lists[i];
    while (desc) {
      if (desc->type == BT_STRING) {
        rb_gc_mark(desc->str);
      }
      desc = desc->next;
    }
  }
  return 0;
}

void Init_BufferManager(void)
{
  memset(&bm, 0, sizeof(bm));
  bm_trace();

  bm_populate(0);
  bm_populate(3);
  bm_populate(6);
  bm_trace();

  buffer_descriptor *desc;
  int ret = bm_prep_buffer(&desc, BT_MANAGED, 30000);
  if (!ret)
    printf("Got buffer: capacity: %d\n", desc->capacity);
  else
    rb_raise(rb_eRuntimeError, "Failed to get buffer");
  bm_trace();

  printf("Disposing buffer...\n");
  bm_dispose(desc);

  bm_trace();
}
