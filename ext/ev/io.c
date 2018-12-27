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
static void EV_IO_mark(struct EV_IO *io);
static void EV_IO_free(struct EV_IO *io);
static size_t EV_IO_size(struct EV_IO *io);

static VALUE EV_IO_initialize(VALUE self, VALUE io, VALUE event_mask);

static VALUE EV_IO_start(VALUE self);
static VALUE EV_IO_stop(VALUE self);
static VALUE EV_IO_await(VALUE self);

void EV_IO_callback(ev_loop *ev_loop, struct ev_io *io, int revents);

static int EV_IO_symbol2event_mask(VALUE sym);

static ID ID_call     = Qnil;
static ID ID_raise    = Qnil;
static ID ID_transfer = Qnil;
static ID ID_R        = Qnil;
static ID ID_W        = Qnil;
static ID ID_RW       = Qnil;

void Init_EV_IO() {
  mEV = rb_define_module("EV");
  cEV_IO = rb_define_class_under(mEV, "IO", rb_cData);
  rb_define_alloc_func(cEV_IO, EV_IO_allocate);

  rb_define_method(cEV_IO, "initialize", EV_IO_initialize, 2);
  rb_define_method(cEV_IO, "start", EV_IO_start, 0);
  rb_define_method(cEV_IO, "stop", EV_IO_stop, 0);
  rb_define_method(cEV_IO, "await", EV_IO_await, 0);

  ID_call     = rb_intern("call");
  ID_raise    = rb_intern("raise");
  ID_transfer = rb_intern("transfer");
  ID_R        = rb_intern("r");
  ID_W        = rb_intern("w");
  ID_RW       = rb_intern("rw");
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

static void EV_IO_mark(struct EV_IO *io) {
  if (io->callback != Qnil) {
    rb_gc_mark(io->callback);
  }
  if (io->fiber != Qnil) {
    rb_gc_mark(io->fiber);
  }
}

static void EV_IO_free(struct EV_IO *io) {
  ev_io_stop(EV_DEFAULT, &io->ev_io);
  xfree(io);
}

static size_t EV_IO_size(struct EV_IO *io) {
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

  // fiber is resumed, check if resumed value is an exception
  if (RTEST(rb_obj_is_kind_of(ret, rb_eException))) {
    if (io->active) {
      io->active = 0;
      ev_io_stop(EV_DEFAULT, &io->ev_io);
    }
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
      RSTRING_PTR(rb_funcall(sym, rb_intern("inspect"), 0)));
  }
}
