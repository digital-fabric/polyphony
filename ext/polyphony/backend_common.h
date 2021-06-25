#ifndef BACKEND_COMMON_H
#define BACKEND_COMMON_H

#include "ruby.h"
#include "ruby/io.h"

struct Backend_base {
  unsigned int currently_polling;
  unsigned int pending_count;
  double idle_gc_period;
  double idle_gc_last_time;
  VALUE idle_block;
};

void initialize_backend_base(struct Backend_base *base);

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
void backend_run_idle_tasks(struct Backend_base *base);
void io_verify_blocking_mode(rb_io_t *fptr, VALUE io, VALUE blocking);

#endif /* BACKEND_COMMON_H */