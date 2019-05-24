#include "ev.h"

#ifdef GetReadFile
# define FPTR_TO_FD(fptr) (fileno(GetReadFile(fptr)))
#else
# define FPTR_TO_FD(fptr) fptr->fd
#endif /* GetReadFile */

struct EV_IO {
  struct  ev_io ev_io;
  int     active;
  int     event_mask;
  VALUE   callback;
  VALUE   fiber;
};

static VALUE mEV = Qnil;
static VALUE cEV_IO = Qnil;

static VALUE EV_IO_allocate(VALUE klass);
static void EV_IO_mark(void *ptr);
static void EV_IO_free(void *ptr);
static size_t EV_IO_size(const void *ptr);

static VALUE EV_IO_initialize(VALUE self, VALUE io, VALUE event_mask);

static VALUE EV_IO_start(VALUE self);
static VALUE EV_IO_stop(VALUE self);
static VALUE EV_IO_await(VALUE self);

void EV_IO_callback(ev_loop *ev_loop, struct ev_io *io, int revents);

static int EV_IO_symbol2event_mask(VALUE sym);

// static VALUE IO_gets(int argc, VALUE *argv, VALUE io);
static VALUE IO_read(int argc, VALUE *argv, VALUE io);
static VALUE IO_readpartial(int argc, VALUE *argv, VALUE io);
static VALUE IO_write(int argc, VALUE *argv, VALUE io);
static VALUE IO_write_chevron(VALUE io, VALUE str);

static VALUE IO_read_watcher(VALUE self);
static VALUE IO_write_watcher(VALUE self);

void Init_EV_IO() {
  mEV = rb_define_module("EV");
  cEV_IO = rb_define_class_under(mEV, "IO", rb_cData);
  rb_define_alloc_func(cEV_IO, EV_IO_allocate);

  rb_define_method(cEV_IO, "initialize", EV_IO_initialize, 2);
  rb_define_method(cEV_IO, "start", EV_IO_start, 0);
  rb_define_method(cEV_IO, "stop", EV_IO_stop, 0);
  rb_define_method(cEV_IO, "await", EV_IO_await, 0);

  VALUE cIO = rb_const_get(rb_cObject, rb_intern("IO"));
  // rb_define_method(cIO, "gets", IO_gets, -1);
  rb_define_method(cIO, "read", IO_read, -1);
  rb_define_method(cIO, "readpartial", IO_readpartial, -1);
  rb_define_method(cIO, "write", IO_write, -1);
  rb_define_method(cIO, "write_nonblock", IO_write, -1);
  rb_define_method(cIO, "<<", IO_write_chevron, 1);
  rb_define_method(cIO, "read_watcher", IO_read_watcher, 0);
  rb_define_method(cIO, "write_watcher", IO_write_watcher, 0);
}

static const rb_data_type_t EV_IO_type = {
    "EV_IO",
    {EV_IO_mark, EV_IO_free, EV_IO_size,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE EV_IO_allocate(VALUE klass) {
  struct EV_IO *io = (struct EV_IO *)xmalloc(sizeof(struct EV_IO));

  return TypedData_Wrap_Struct(klass, &EV_IO_type, io);
}

static void EV_IO_mark(void *ptr) {
  struct EV_IO *io = ptr;
  if (io->callback != Qnil) {
    rb_gc_mark(io->callback);
  }
  if (io->fiber != Qnil) {
    rb_gc_mark(io->fiber);
  }
}

static void EV_IO_free(void *ptr) {
  struct EV_IO *io = ptr;
  ev_io_stop(EV_DEFAULT, &io->ev_io);
  xfree(io);
}

static size_t EV_IO_size(const void *ptr) {
  return sizeof(struct EV_IO);
}

static const char * S_IO = "IO";
static const char * S_to_io = "to_io";

#define GetEV_IO(obj, io) TypedData_Get_Struct((obj), struct EV_IO, &EV_IO_type, (io))

static VALUE EV_IO_initialize(VALUE self, VALUE io_obj, VALUE event_mask) {
  struct EV_IO *io;
  rb_io_t *fptr;

  GetEV_IO(self, io);

  io->event_mask = EV_IO_symbol2event_mask(event_mask);
  io->callback = Qnil;
  io->fiber = Qnil;
  io->active = 0;

  GetOpenFile(rb_convert_type(io_obj, T_FILE, S_IO, S_to_io), fptr);
  ev_io_init(&io->ev_io, EV_IO_callback, FPTR_TO_FD(fptr), io->event_mask);

  return Qnil;
}

void EV_IO_callback(ev_loop *ev_loop, struct ev_io *ev_io, int revents) {
  VALUE fiber;
  struct EV_IO *io = (struct EV_IO*)ev_io;

  if (io->fiber != Qnil) {
    ev_io_stop(EV_DEFAULT, ev_io);
    io->active = 0;
    fiber = io->fiber;
    io->fiber = Qnil;
    SCHEDULE_FIBER(fiber, 0);
  }
  else if (io->callback != Qnil) {
    rb_funcall(io->callback, ID_call, 1, INT2NUM(revents));
  }
  else {
    ev_io_stop(EV_DEFAULT, ev_io);
  }
}

static VALUE EV_IO_start(VALUE self) {
  struct EV_IO *io;
  GetEV_IO(self, io);

  if (rb_block_given_p()) {
    io->callback = rb_block_proc();
  }

  if (!io->active) {
    ev_io_start(EV_DEFAULT, &io->ev_io);
    io->active = 1;
  }

  return self;
}

static VALUE EV_IO_stop(VALUE self) {
  struct EV_IO *io;
  GetEV_IO(self, io);

  if (io->active) {
    ev_io_stop(EV_DEFAULT, &io->ev_io);
    io->active = 0;
  }

  return self;
}

static VALUE EV_IO_await(VALUE self) {
  struct EV_IO *io;
  VALUE ret;
  
  GetEV_IO(self, io);

  io->fiber = rb_fiber_current();
  io->active = 1;
  ev_io_start(EV_DEFAULT, &io->ev_io);
  ret = YIELD_TO_REACTOR();

  // make sure io watcher is stopped
  if (io->active) {
    io->active = 0;
    ev_io_stop(EV_DEFAULT, &io->ev_io);
  }

  // fiber is resumed, check if resumed value is an exception
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    return rb_funcall(ret, ID_raise, 1, ret);
  }
  else {
    return Qnil;
  }
}

static int EV_IO_symbol2event_mask(VALUE sym) {
  ID sym_id;

  if (NIL_P(sym)) {
    return 0;
  }

  sym_id = SYM2ID(sym);

  if(sym_id == ID_R) {
    return EV_READ;
  } else if(sym_id == ID_W) {
    return EV_WRITE;
  } else if(sym_id == ID_RW) {
    return EV_READ | EV_WRITE;
  } else {
    rb_raise(rb_eArgError, "invalid interest type %s (must be :r, :w, or :rw)",
      RSTRING_PTR(rb_funcall(sym, ID_inspect, 0)));
  }
}

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////
// the following is copied verbatim from the Ruby source code (io.c)
struct io_internal_read_struct {
    int fd;
    int nonblock;
    void *buf;
    size_t capa;
};

static int io_setstrbuf(VALUE *str, long len) {
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

static void io_set_read_length(VALUE str, long n, int shrinkable) {
  if (RSTRING_LEN(str) != n) {
    rb_str_modify(str);
    rb_str_set_len(str, n);
    if (shrinkable) io_shrink_read_string(str, n);
  }
}

static rb_encoding*
io_read_encoding(rb_io_t *fptr)
{
    if (fptr->encs.enc) {
	return fptr->encs.enc;
    }
    return rb_default_external_encoding();
}

static VALUE io_enc_str(VALUE str, rb_io_t *fptr)
{
    OBJ_TAINT(str);
    rb_enc_associate(str, io_read_encoding(fptr));
    return str;
}

//////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////

static VALUE IO_read(int argc, VALUE *argv, VALUE io) {
  long len = argc == 1 ? NUM2LONG(argv[0]) : 8192;

  rb_io_t *fptr;
  long n;
  int shrinkable;
  VALUE read_watcher = Qnil;

  if (len < 0) {
    rb_raise(rb_eArgError, "negative length %ld given", len);
  }

  VALUE str = argc >= 2 ? argv[1] : Qnil;

  shrinkable = io_setstrbuf(&str, len);
  // OBJ_TAINT(str);
  GetOpenFile(io, fptr);
  rb_io_check_byte_readable(fptr);
  rb_io_set_nonblock(fptr);

  if (len == 0)
  	return str;
  
  char *buf = RSTRING_PTR(str);
  long total = 0;

  while (1) {
    n = read(fptr->fd, buf, len);
    if (n < 0) {
      int e = errno;
      if ((e == EWOULDBLOCK || e == EAGAIN)) {
        if (read_watcher == Qnil)
          // read_watcher = IO_read_watcher(io);
          read_watcher = rb_funcall(io, ID_read_watcher, 0);
        EV_IO_await(read_watcher);
      }
      else
        rb_syserr_fail(e, strerror(e));
        // rb_syserr_fail_path(e, fptr->pathv);
    }
    else if (n == 0)
      break;
    else {
      total = total + n;
      buf += n;
      len -= n;
      if (len == 0)
        break;
    }
  }

  if (total == 0)
    return Qnil;

  io_set_read_length(str, total, shrinkable);
  io_enc_str(str, fptr);

  return str;
}

static VALUE IO_readpartial(int argc, VALUE *argv, VALUE io) {
  long len = argc == 1 ? NUM2LONG(argv[0]) : 8192;

  rb_io_t *fptr;
  long n;
  int shrinkable;
  VALUE read_watcher = Qnil;

  if (len < 0) {
    rb_raise(rb_eArgError, "negative length %ld given", len);
  }

  VALUE str = argc >= 2 ? argv[1] : Qnil;

  shrinkable = io_setstrbuf(&str, len);
  OBJ_TAINT(str);
  GetOpenFile(io, fptr);
  rb_io_set_nonblock(fptr);
  rb_io_check_byte_readable(fptr);

  if (len == 0)
  	return str;

  while (1) {
    n = read(fptr->fd, RSTRING_PTR(str), len);
    if (n < 0) {
      int e = errno;
      if ((e == EWOULDBLOCK || e == EAGAIN)) {
        if (read_watcher == Qnil)
          // read_watcher = IO_read_watcher(io);
          read_watcher = rb_funcall(io, ID_read_watcher, 0);
        EV_IO_await(read_watcher);
      }
      else
        rb_syserr_fail(e, strerror(e));
        // rb_syserr_fail_path(e, fptr->pathv);
    }
    else
      break;
  }

  io_set_read_length(str, n, shrinkable);
  io_enc_str(str, fptr);

  if (n == 0)
    return Qnil;

  return str;
}

static VALUE IO_write(int argc, VALUE *argv, VALUE io) {
  long i;
  long n;
  long total = 0;
  rb_io_t *fptr;

  io = rb_io_get_write_io(io);
  VALUE write_watcher = Qnil;

  GetOpenFile(io, fptr);
  rb_io_check_writable(fptr);
  rb_io_set_nonblock(fptr);

  for (i = 0; i < argc; i++) {
    VALUE str = argv[i];
    if (!RB_TYPE_P(str, T_STRING))
	    str = rb_obj_as_string(str);
    char *buf = RSTRING_PTR(str);
    long len = RSTRING_LEN(str);
    RB_GC_GUARD(str);
    while (1) {
      n = write(fptr->fd, buf, len);

      if (n < 0) {
        int e = errno;
        if (e == EWOULDBLOCK || e == EAGAIN) {
          if (write_watcher == Qnil)
            // write_watcher = IO_write_watcher(io);
            write_watcher = rb_funcall(io, ID_write_watcher, 0);
          EV_IO_await(write_watcher);
        }
        else {
          rb_syserr_fail(e, strerror(e));
          // rb_syserr_fail_path(e, fptr->pathv);
        }
      }
      else {
        total += n;
        if (n < len) {
          buf += n;
          len -= n;
        }
        else break;
      }
    }
  }

  return LONG2FIX(total);
}

static VALUE IO_write_chevron(VALUE io, VALUE str) {
  IO_write(1, &str, io);
  return io;
}

static VALUE IO_read_watcher(VALUE self) {
  VALUE watcher = rb_iv_get(self, "@read_watcher");
  if (watcher == Qnil) {
    watcher = rb_funcall(cEV_IO, rb_intern("new"), 2, self, ID2SYM(rb_intern("r")));
    rb_iv_set(self, "@read_watcher", watcher);
  }
  return watcher;
}

static VALUE IO_write_watcher(VALUE self) {
  VALUE watcher = rb_iv_get(self, "@write_watcher");
  if (watcher == Qnil) {
    watcher = rb_funcall(cEV_IO, rb_intern("new"), 2, self, ID2SYM(rb_intern("w")));
    rb_iv_set(self, "@write_watcher", watcher);
  }
  return watcher;
}
