#ifndef BACKEND_H
#define BACKEND_H

#include "ruby.h"

typedef VALUE (* backend_pending_count_t)(VALUE self);
typedef VALUE (*backend_poll_t)(VALUE self, VALUE nowait, VALUE current_fiber, VALUE runqueue);
typedef VALUE (* backend_ref_t)(VALUE self);
typedef int (* backend_ref_count_t)(VALUE self);
typedef void (* backend_reset_ref_count_t)(VALUE self);
typedef VALUE (* backend_unref_t)(VALUE self);
typedef VALUE (* backend_wait_event_t)(VALUE self, VALUE raise_on_exception);
typedef VALUE (* backend_wakeup_t)(VALUE self);

typedef struct backend_interface {
  backend_pending_count_t   pending_count;
  backend_poll_t            poll;
  backend_ref_t             ref;
  backend_ref_count_t       ref_count;
  backend_reset_ref_count_t reset_ref_count;
  backend_unref_t           unref;
  backend_wait_event_t      wait_event;
  backend_wakeup_t          wakeup;
} backend_interface_t;

#endif /* BACKEND_H */