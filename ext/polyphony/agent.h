#ifndef AGENT_H
#define AGENT_H

#include "ruby.h"

// agent interface function signatures 

// VALUE LibevAgent_accept(VALUE self, VALUE sock);
// VALUE LibevAgent_accept_loop(VALUE self, VALUE sock);
// VALUE libev_agent_await(VALUE self);
// VALUE LibevAgent_connect(VALUE self, VALUE sock, VALUE host, VALUE port);
// VALUE LibevAgent_finalize(VALUE self);
// VALUE LibevAgent_post_fork(VALUE self);
// VALUE LibevAgent_read(VALUE self, VALUE io, VALUE str, VALUE length, VALUE to_eof);
// VALUE LibevAgent_read_loop(VALUE self, VALUE io);
// VALUE LibevAgent_ref(VALUE self);
// VALUE LibevAgent_sleep(VALUE self, VALUE duration);
// VALUE LibevAgent_unref(VALUE self);
// VALUE LibevAgent_wait_io(VALUE self, VALUE io, VALUE write);
// VALUE LibevAgent_wait_pid(VALUE self, VALUE pid);
// VALUE LibevAgent_write(int argc, VALUE *argv, VALUE self);

typedef VALUE (* agent_pending_count_t)(VALUE self);
typedef VALUE (*agent_poll_t)(VALUE self, VALUE nowait, VALUE current_fiber, VALUE queue);
typedef int (* agent_ref_count_t)(VALUE self);
typedef void (* agent_reset_ref_count_t)(VALUE self);
typedef VALUE (* agent_wait_event_t)(VALUE self, VALUE raise_on_exception);
typedef VALUE (* agent_wakeup_t)(VALUE self);

typedef struct agent_interface {
  agent_pending_count_t   pending_count;
  agent_poll_t            poll;
  agent_ref_count_t       ref_count;
  agent_reset_ref_count_t reset_ref_count;
  agent_wait_event_t      wait_event;
  agent_wakeup_t          wakeup;
} agent_interface_t;

#endif /* AGENT_H */