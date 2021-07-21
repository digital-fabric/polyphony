#ifndef BACKEND_COMMON_H
#define BACKEND_COMMON_H

#include "ruby.h"
#include "ruby/io.h"
#include "runqueue.h"

struct backend_stats {
  unsigned int runqueue_size;
  unsigned int runqueue_length;
  unsigned int runqueue_max_length;
  unsigned int op_count;
  unsigned int switch_count;
  unsigned int poll_count;
  unsigned int pending_ops;
};

struct Backend_base {
  runqueue_t runqueue;
  unsigned int currently_polling;
  unsigned int op_count;
  unsigned int switch_count;
  unsigned int poll_count;
  unsigned int pending_count;
  double idle_gc_period;
  double idle_gc_last_time;
  VALUE idle_proc;
  VALUE trace_proc;
};

void backend_base_initialize(struct Backend_base *base);
void backend_base_finalize(struct Backend_base *base);
void backend_base_mark(struct Backend_base *base);
VALUE backend_base_switch_fiber(VALUE backend, struct Backend_base *base);
void backend_base_schedule_fiber(VALUE thread, VALUE backend, struct Backend_base *base, VALUE fiber, VALUE value, int prioritize);
void backend_trace(struct Backend_base *base, int argc, VALUE *argv);
struct backend_stats backend_base_stats(struct Backend_base *base);

// tracing
#define SHOULD_TRACE(base) ((base)->trace_proc != Qnil)
#define TRACE(base, ...)  rb_funcall((base)->trace_proc, ID_call, __VA_ARGS__)
#define COND_TRACE(base, ...) if (SHOULD_TRACE(base)) { TRACE(base, __VA_ARGS__); }



#ifdef POLYPHONY_USE_PIDFD_OPEN
int pidfd_open(pid_t pid, unsigned int flags);
#endif

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////
// the following is copied verbatim from the Ruby source code (io.c)
struct io_internal_read_struct {
    int fd;
    int nonblock;
    void *buf;
    size_t capa;
};

#define StringValue(v) rb_string_value(&(v))

int io_setstrbuf(VALUE *str, long len);
void io_shrink_read_string(VALUE str, long n);
void io_set_read_length(VALUE str, long n, int shrinkable);
rb_encoding* io_read_encoding(rb_io_t *fptr);
VALUE io_enc_str(VALUE str, rb_io_t *fptr);

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////

struct backend_stats backend_get_stats(VALUE self);
VALUE backend_await(struct Backend_base *backend);
VALUE backend_snooze();

// macros for doing read loops
#define READ_LOOP_PREPARE_STR() { \
  str = Qnil; \
  shrinkable = io_setstrbuf(&str, len); \
  buf = RSTRING_PTR(str); \
  total = 0; \
  OBJ_TAINT(str); \
}

#define READ_LOOP_YIELD_STR() { \
  io_set_read_length(str, total, shrinkable); \
  io_enc_str(str, fptr); \
  rb_yield(str); \
  READ_LOOP_PREPARE_STR(); \
}

#define READ_LOOP_PASS_STR_TO_RECEIVER(receiver, method_id) { \
  io_set_read_length(str, total, shrinkable); \
  io_enc_str(str, fptr); \
  rb_funcall_passing_block(receiver, method_id, 1, &str); \
  READ_LOOP_PREPARE_STR(); \
}

void rectify_io_file_pos(rb_io_t *fptr);
double current_time();
VALUE backend_timeout_exception(VALUE exception);
VALUE Backend_timeout_ensure_safe(VALUE arg);
VALUE Backend_timeout_ensure_safe(VALUE arg);
VALUE Backend_sendv(VALUE self, VALUE io, VALUE ary, VALUE flags);
VALUE Backend_stats(VALUE self);
void backend_run_idle_tasks(struct Backend_base *base);
void io_verify_blocking_mode(rb_io_t *fptr, VALUE io, VALUE blocking);

void backend_setup_stats_symbols();

#endif /* BACKEND_COMMON_H */