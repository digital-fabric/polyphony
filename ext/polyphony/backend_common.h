#include <time.h>

#include "ruby.h"
#include "ruby/io.h"


#ifdef POLYPHONY_USE_PIDFD_OPEN
#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434   /* System call # on most architectures */
#endif

static int pidfd_open(pid_t pid, unsigned int flags) {
  return syscall(__NR_pidfd_open, pid, flags);
}
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

inline int io_setstrbuf(VALUE *str, long len) {
  #ifdef _WIN32
    len = (len + 1) & ~1L;	/* round up for wide char */
  #endif
  if (*str == Qnil) {
    *str = rb_str_new(0, len);
    return 1;
  }
  else {
    VALUE s = StringValue(*str);
    long clen = RSTRING_LEN(s);
    if (clen >= len) {
      rb_str_modify(s);
      return 0;
    }
    len -= clen;
  }
  rb_str_modify_expand(*str, len);
  return 0;
}

#define MAX_REALLOC_GAP 4096

inline void io_shrink_read_string(VALUE str, long n) {
  if (rb_str_capacity(str) - n > MAX_REALLOC_GAP) {
    rb_str_resize(str, n);
  }
}

inline void io_set_read_length(VALUE str, long n, int shrinkable) {
  if (RSTRING_LEN(str) != n) {
    rb_str_modify(str);
    rb_str_set_len(str, n);
    if (shrinkable) io_shrink_read_string(str, n);
  }
}

inline rb_encoding* io_read_encoding(rb_io_t *fptr) {
  if (fptr->encs.enc) {
	  return fptr->encs.enc;
  }
  return rb_default_external_encoding();
}

inline VALUE io_enc_str(VALUE str, rb_io_t *fptr) {
  OBJ_TAINT(str);
  rb_enc_associate(str, io_read_encoding(fptr));
  return str;
}

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////

inline VALUE backend_await(Backend_t *backend) {
  VALUE ret;
  backend->pending_count++;
  ret = Thread_switch_fiber(rb_thread_current());
  backend->pending_count--;
  RB_GC_GUARD(ret);
  return ret;
}

inline VALUE backend_snooze() {
  Fiber_make_runnable(rb_fiber_current(), Qnil);
  return Thread_switch_fiber(rb_thread_current());
}

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

inline void rectify_io_file_pos(rb_io_t *fptr) {
  // Apparently after reopening a closed file, the file position is not reset,
  // which causes the read to fail. Fortunately we can use fptr->rbuf.len to
  // find out if that's the case.
  // See: https://github.com/digital-fabric/polyphony/issues/30
  if (fptr->rbuf.len > 0) {
    lseek(fptr->fd, -fptr->rbuf.len, SEEK_CUR);
    fptr->rbuf.len = 0;
  }
}

inline double current_time() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  long long ns = ts.tv_sec;
  ns = ns * 1e9 + ts.tv_nsec;
  double t = ns;
  return t / 1e9;
}

inline VALUE backend_timeout_exception(VALUE exception) {
  if (rb_obj_is_kind_of(exception, rb_cArray) == Qtrue)
    return rb_funcall(rb_ary_entry(exception, 0), ID_new, 1, rb_ary_entry(exception, 1));
  else if (rb_obj_is_kind_of(exception, rb_cClass) == Qtrue)
    return rb_funcall(exception, ID_new, 0);
  else
    return rb_funcall(rb_eRuntimeError, ID_new, 1, exception);
}

VALUE Backend_timeout_safe(VALUE arg) {
  return rb_yield(arg);
}

VALUE Backend_timeout_rescue(VALUE arg, VALUE exception) {
  return exception;
}

VALUE Backend_timeout_ensure_safe(VALUE arg) {
  return rb_rescue2(Backend_timeout_safe, Qnil, Backend_timeout_rescue, Qnil, rb_eException, (VALUE)0);
}

static VALUE empty_string = Qnil;

VALUE Backend_sendv(VALUE self, VALUE io, VALUE ary, VALUE flags) {
  switch (RARRAY_LEN(ary)) {
  case 0:
    return Qnil;
  case 1:
    return Backend_send(self, io, RARRAY_AREF(ary, 0), flags);
  default:
    if (empty_string == Qnil) {
      empty_string = rb_str_new_literal("");
      rb_global_variable(&empty_string);
    }
    VALUE joined = rb_ary_join(ary, empty_string);
    VALUE result = Backend_send(self, io, joined, flags);
    RB_GC_GUARD(joined);
    return result;
  }
}

inline void io_verify_blocking_mode(rb_io_t *fptr, VALUE io, VALUE blocking) {
  VALUE blocking_mode = rb_ivar_get(io, ID_ivar_blocking_mode);
  if (blocking == blocking_mode) return;

  rb_ivar_set(io, ID_ivar_blocking_mode, blocking);

#ifdef _WIN32
  if (blocking != Qtrue)
    rb_w32_set_nonblock(fptr->fd);
#elif defined(F_GETFL)
  int oflags = fcntl(fptr->fd, F_GETFL);
  if (oflags == -1) return;
  int is_nonblocking = oflags & O_NONBLOCK;
  
  if (blocking == Qtrue) {
    if (!is_nonblocking) return;
    oflags &= ~O_NONBLOCK;
  } else {
    if (is_nonblocking) return;
    oflags |= O_NONBLOCK;
  }
  fcntl(fptr->fd, F_SETFL, oflags);
#endif
}
