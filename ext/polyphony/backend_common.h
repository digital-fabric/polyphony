#ifndef BACKEND_COMMON_H
#define BACKEND_COMMON_H

#include <sys/types.h>
#ifdef POLYPHONY_WINDOWS
#include <winsock2.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netdb.h>
#include <sys/socket.h>
#endif

#include "ruby.h"
#include "ruby/io.h"
#include "runqueue.h"

extern VALUE cBackend;

#ifndef HAVE_RB_IO_DESCRIPTOR
static int rb_io_descriptor_fallback(VALUE io) {
  rb_io_t *fptr;
  GetOpenFile(io, fptr);
  return fptr->fd;
}
#define rb_io_descriptor rb_io_descriptor_fallback
#endif

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
  runqueue_t parked_runqueue;
  unsigned int currently_polling;
  unsigned int op_count;
  unsigned int switch_count;
  unsigned int poll_count;
  unsigned int pending_count;
  double idle_gc_period;
  double idle_gc_last_time;
  VALUE idle_proc;
  VALUE trace_proc;
  unsigned int in_trace_proc;
};

void backend_base_initialize(struct Backend_base *base);
void backend_base_finalize(struct Backend_base *base);
void backend_base_mark(struct Backend_base *base);
void backend_base_reset(struct Backend_base *base);
VALUE backend_base_switch_fiber(VALUE backend, struct Backend_base *base);
void backend_base_schedule_fiber(VALUE thread, VALUE backend, struct Backend_base *base, VALUE fiber, VALUE value, int prioritize);
void backend_base_park_fiber(struct Backend_base *base, VALUE fiber);
void backend_base_unpark_fiber(struct Backend_base *base, VALUE fiber);
void backend_trace(struct Backend_base *base, int argc, VALUE *argv);
struct backend_stats backend_base_stats(struct Backend_base *base);

// tracing
#define SHOULD_TRACE(base) unlikely((base)->trace_proc != Qnil && !(base)->in_trace_proc)
#define TRACE(base, ...) { \
  (base)->in_trace_proc = 1; \
  rb_funcall((base)->trace_proc, ID_call, __VA_ARGS__); \
  (base)->in_trace_proc = 0; \
}
#define COND_TRACE(base, ...) if (SHOULD_TRACE(base)) { TRACE(base, __VA_ARGS__); }

// buffers

struct buffer_spec {
  unsigned char *ptr;
  int len;
};

struct backend_buffer_spec {
  unsigned char *ptr;
  int len;
  int raw;
  int pos;
  int expandable:1;
  int shrinkable:1;
  int reserved:30;
};

#define FIX2PTR(v) ((void *)(FIX2LONG(v)))
#define PTR2FIX(p) LONG2FIX((long)p)

struct backend_buffer_spec backend_get_buffer_spec(VALUE in, int rw);
void backend_prepare_read_buffer(VALUE buffer, VALUE length, struct backend_buffer_spec *buffer_spec, int pos);
void backend_grow_string_buffer(VALUE buffer, struct backend_buffer_spec *buffer_spec, int total);
void backend_finalize_string_buffer(VALUE buffer, struct backend_buffer_spec *buffer_spec, int total, rb_io_t *fptr);

VALUE coerce_io_string_or_buffer(VALUE buf);

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
void fptr_finalize(rb_io_t *fptr);

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////

struct backend_stats backend_get_stats(VALUE self);
VALUE backend_await(struct Backend_base *backend);
VALUE backend_snooze(struct Backend_base *backend);

// macros for doing read loops
#define READ_LOOP_PREPARE_STR() { \
  buffer = Qnil; \
  shrinkable = io_setstrbuf(&buffer, len); \
  ptr = RSTRING_PTR(buffer); \
  total = 0; \
}

#define READ_LOOP_YIELD_STR() { \
  io_set_read_length(buffer, total, shrinkable); \
  if (fptr) io_enc_str(buffer, fptr); \
  rb_yield(buffer); \
  READ_LOOP_PREPARE_STR(); \
}

#define READ_LOOP_PASS_STR_TO_RECEIVER(receiver, method_id) { \
  io_set_read_length(buffer, total, shrinkable); \
  if (fptr) io_enc_str(buffer, fptr); \
  rb_funcall_passing_block(receiver, method_id, 1, &buffer); \
  READ_LOOP_PREPARE_STR(); \
}

void rectify_io_file_pos(rb_io_t *fptr);
double current_time();
uint64_t current_time_ns();
VALUE backend_timeout_exception(VALUE exception);
VALUE Backend_timeout_ensure_safe(VALUE arg);
VALUE Backend_timeout_ensure_safe(VALUE arg);
VALUE Backend_sendv(VALUE self, VALUE io, VALUE ary, VALUE flags);
VALUE Backend_stats(VALUE self);
VALUE Backend_verify_blocking_mode(VALUE self, VALUE io, VALUE blocking);
void backend_run_idle_tasks(struct Backend_base *base);
void set_fd_blocking_mode(int fd, int blocking);
void io_verify_blocking_mode(VALUE io, int fd, VALUE blocking);
void backend_setup_stats_symbols();
int backend_getaddrinfo(VALUE host, VALUE port, struct sockaddr **ai_addr);
VALUE name_to_addrinfo(void *name, socklen_t len);

#endif /* BACKEND_COMMON_H */
