#ifndef BUFFERS_H
#define BUFFERS_H

#include "ruby.h"

enum buffer_type {
  BT_SINGLE_USE,
  BT_MANAGED,
  BT_STRING,
};

typedef struct buffer_descriptor {
  enum buffer_type type;
  union {
    struct {
      VALUE str;
    };
    struct {
      int gid;
      int id;
    };
  };
  char * ptr;
  unsigned int len;
  unsigned int capacity;

  struct buffer_descriptor *prev;
  struct buffer_descriptor *next;
} buffer_descriptor;

 // 4K to 4G
#define FREE_LIST_MIN_POWER_OF_TWO 12
#define FREE_LIST_MAX_POWER_OF_TWO 32
#define FREE_LIST_COUNT 20
#define FREE_LIST_IDX(power_of_two) (power_of_two - FREE_LIST_MIN_POWER_OF_TWO)

typedef struct {
  buffer_descriptor *free_lists[FREE_LIST_COUNT];
} buffer_manager;

int bm_prep_buffer(buffer_descriptor **desc, enum buffer_type type, size_t len);
int bm_buffer_from_string(buffer_descriptor **desc, VALUE str);
int bm_dispose(buffer_descriptor *desc);
int bm_mark(void);

void bm_reset(void);
void bm_get_status(VALUE hash);

#endif /* BUFFERS_H */
