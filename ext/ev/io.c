#include "ev.h"

struct EV_IO
{
    VALUE self;
    int event_mask;
    int active;
    struct ev_io ev_io;
    VALUE callback;
};

static VALUE mEV = Qnil;
static VALUE cEV_IO = Qnil;

static VALUE EV_IO_allocate(VALUE klass);
static void EV_IO_mark(struct EV_IO *io);
static void EV_IO_free(struct EV_IO *io);

static VALUE EV_IO_initialize(VALUE self, VALUE io, VALUE event_mask, VALUE start);

static VALUE EV_IO_start(VALUE self);
static VALUE EV_IO_stop(VALUE self);

void EV_IO_callback(ev_loop *ev_loop, struct ev_io *io, int revents);

// static VALUE EV_IO_event_mask(VALUE self);
// static VALUE EV_IO_set_event_mask(VALUE self, VALUE sym);

static int EV_IO_symbol2event_mask(VALUE sym);

// static void EV_IO_update_event_mask(VALUE self, int event_mask);

static ID ID_R        = Qnil;
static ID ID_W        = Qnil;
static ID ID_RW       = Qnil;

static ID ID_CALL     = Qnil;

/* IO encapsulates an io watcher */
void Init_EV_IO()
{
  mEV = rb_define_module("EV");
  cEV_IO = rb_define_class_under(mEV, "IO", rb_cObject);
  rb_define_alloc_func(cEV_IO, EV_IO_allocate);

  rb_define_method(cEV_IO, "initialize", EV_IO_initialize, 3);
  rb_define_method(cEV_IO, "start", EV_IO_start, 0);
  rb_define_method(cEV_IO, "stop", EV_IO_stop, 0);
  // rb_define_method(cEV_IO, "event_mask", EV_IO_event_mask, 0);
  // rb_define_method(cEV_IO, "event_mask=", EV_IO_set_event_mask, 1);

  ID_R = rb_intern("r");
  ID_W = rb_intern("w");
  ID_RW = rb_intern("rw");

  ID_CALL = rb_intern("call");
}

static VALUE EV_IO_allocate(VALUE klass)
{
  struct EV_IO *io = (struct EV_IO *)xmalloc(sizeof(struct EV_IO));

  return Data_Wrap_Struct(klass, EV_IO_mark, EV_IO_free, io);
}

static void EV_IO_mark(struct EV_IO *io)
{
  if (io->callback != Qnil) {
    rb_gc_mark(io->callback);
  }
}

static void EV_IO_free(struct EV_IO *io)
{
  ev_io_stop(EV_DEFAULT, &io->ev_io);
  xfree(io);
}

static VALUE EV_IO_initialize(VALUE self, VALUE io_obj, VALUE event_mask, VALUE start)
{
  struct EV_IO *io;
  rb_io_t *fptr;

  Data_Get_Struct(self, struct EV_IO, io);

  io->event_mask = EV_IO_symbol2event_mask(event_mask);
  io->callback = rb_block_proc();

  GetOpenFile(rb_convert_type(io_obj, T_FILE, "IO", "to_io"), fptr);
  ev_io_init(&io->ev_io, EV_IO_callback, FPTR_TO_FD(fptr), io->event_mask);

  // rb_ivar_set(self, rb_intern("io"), io_obj);
  // rb_ivar_set(self, rb_intern("event_mask"), event_mask);

  io->self = self;
  io->ev_io.data = (void *)io;

  io->active = RTEST(start);
  if (io->active) {
    ev_io_start(EV_DEFAULT, &io->ev_io);
  }

  return Qnil;
}

/* libev callback fired on IO event */
void EV_IO_callback(ev_loop *ev_loop, struct ev_io *io, int revents)
{
  struct EV_IO *io_data = (struct EV_IO *)io->data;
  if (io_data->callback != Qnil) {
    rb_funcall(io_data->callback, ID_CALL, 1, revents);
  }
}

static VALUE EV_IO_start(VALUE self)
{
  struct EV_IO *io;
  Data_Get_Struct(self, struct EV_IO, io);

  if (!io->active) {
    ev_io_start(EV_DEFAULT, &io->ev_io);
    io->active = 1;
  }

  return Qnil;
}

static VALUE EV_IO_stop(VALUE self)
{
  struct EV_IO *io;
  Data_Get_Struct(self, struct EV_IO, io);

  if (io->active) {
    ev_io_stop(EV_DEFAULT, &io->ev_io);
    io->active = 0;
  }

  return Qnil;
}

/* Internal C functions */

static int EV_IO_symbol2event_mask(VALUE sym)
{
  if (NIL_P(sym)) {
    return 0;
  }

  ID sym_id;
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
