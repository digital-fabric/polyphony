#include "ruby.h"
#include "ruby/io.h"

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

int io_setstrbuf(VALUE *str, long len) {
  #ifdef _WIN32
    len = (len + 1) & ~1L;	/* round up for wide char */
  #endif
  if (NIL_P(*str)) {
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
static void io_shrink_read_string(VALUE str, long n) {
  if (rb_str_capacity(str) - n > MAX_REALLOC_GAP) {
    rb_str_resize(str, n);
  }
}

void io_set_read_length(VALUE str, long n, int shrinkable) {
  if (RSTRING_LEN(str) != n) {
    rb_str_modify(str);
    rb_str_set_len(str, n);
    if (shrinkable) io_shrink_read_string(str, n);
  }
}

static rb_encoding* io_read_encoding(rb_io_t *fptr) {
    if (fptr->encs.enc) {
	return fptr->encs.enc;
    }
    return rb_default_external_encoding();
}

VALUE io_enc_str(VALUE str, rb_io_t *fptr) {
    OBJ_TAINT(str);
    rb_enc_associate(str, io_read_encoding(fptr));
    return str;
}

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////

inline VALUE backend_await(Backend_t *backend) {
  VALUE ret;
  backend->ref_count++;
  ret = Thread_switch_fiber(rb_thread_current());
  backend->ref_count--;
  RB_GC_GUARD(ret);
  return ret;
}

VALUE backend_snooze() {
  Fiber_make_runnable(rb_fiber_current(), Qnil);
  return Thread_switch_fiber(rb_thread_current());
}

ID ID_ivar_is_nonblocking;

// Since we need to ensure that fd's are non-blocking before every I/O
// operation, here we improve upon Ruby's rb_io_set_nonblock by caching the
// "nonblock" state in an instance variable. Calling rb_ivar_get on every read
// is still much cheaper than doing a fcntl syscall on every read! Preliminary
// benchmarks (with a "hello world" HTTP server) show throughput is improved
// by 10-13%.
inline void io_set_nonblock(rb_io_t *fptr, VALUE io) {
  VALUE is_nonblocking = rb_ivar_get(io, ID_ivar_is_nonblocking);
  if (is_nonblocking == Qtrue) return;

  rb_ivar_set(io, ID_ivar_is_nonblocking, Qtrue);

#ifdef _WIN32
  rb_w32_set_nonblock(fptr->fd);
#elif defined(F_GETFL)
  int oflags = fcntl(fptr->fd, F_GETFL);
  if ((oflags == -1) && (oflags & O_NONBLOCK)) return;
  oflags |= O_NONBLOCK;
  fcntl(fptr->fd, F_SETFL, oflags);
#endif
}

