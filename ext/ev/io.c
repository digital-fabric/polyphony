#include "ev.h"

static VALUE mEV = Qnil;
static VALUE cEV_IO = Qnil;

static VALUE EV_IO_allocate(VALUE klass);
static void EV_IO_mark(struct EV_IO *io);
static void EV_IO_free(struct EV_IO *io);

static VALUE EV_IO_initialize(VALUE self, VALUE io, VALUE events, VALUE opts);

static VALUE EV_IO_start(VALUE self);
static VALUE EV_IO_stop(VALUE self);

void EV_IO_callback(ev_loop *ev_loop, struct ev_io *io, int revents);

static VALUE EV_IO_event_mask(VALUE self);
static VALUE EV_IO_set_event_mask(VALUE self, VALUE sym);

static int EV_IO_symbol2event_mask(VALUE sym);

static void EV_IO_update_event_mask(VALUE self, int event_mask);

static ID ID_R        = Qnil;
static ID ID_W        = Qnil;
static ID ID_RW       = Qnil;

static ID ID_READABLE = Qnil;
static ID ID_WRITABLE = Qnil;

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
  rb_define_method(cEV_IO, "event_mask", EV_IO_event_mask, 0);
  rb_define_method(cEV_IO, "event_mask=", EV_IO_set_event_mask, 1);

  ID_R = rb_intern("r");
  ID_W = rb_intern("w");
  ID_RW = rb_intern("rw");

  ID_READABLE = rb_intern("readable");
  ID_WRITABLE = rb_intern("writable");

  ID_CALL = rb_intern("call");
}

static VALUE EV_IO_allocate(VALUE klass)
{
  struct EV_IO *io = (struct EV_IO *)xmalloc(sizeof(struct EV_IO));

  return Data_Wrap_Struct(klass, EV_IO_mark, EV_IO_free, io);
}

static void EV_IO_mark(struct EV_IO *io)
{
  rb_gc_mark(io->readable_callback);
  rb_gc_mark(io->writable_callback);
}

static void EV_IO_free(struct EV_IO *io)
{
  xfree(io);
}

static VALUE EV_IO_initialize(VALUE self, VALUE io_obj, VALUE events, VALUE opts)
{
  struct EV_IO *io;
  rb_io_t *fptr;

  Data_Get_Struct(self, struct EV_IO, io);

  io->event_mask = EV_IO_symbol2event_mask(events);

  io->readable_callback = rb_hash_aref(opts, ID2SYM(ID_READABLE));
  io->writable_callback = rb_hash_aref(opts, ID2SYM(ID_WRITABLE));

  GetOpenFile(rb_convert_type(io_obj, T_FILE, "IO", "to_io"), fptr);
  ev_io_init(&io->ev_io, EV_IO_callback, FPTR_TO_FD(fptr), io->event_mask);

  rb_ivar_set(self, rb_intern("io"), io_obj);
  rb_ivar_set(self, rb_intern("event_mask"), events);

  io->self = self;
  io->ev_io.data = (void *)io;

  if (io->event_mask) {
    ev_io_start(EV_DEFAULT, &io->ev_io);
  }

  return Qnil;
}

/* libev callback fired on IO event */
void EV_IO_callback(ev_loop *ev_loop, struct ev_io *io, int revents)
{
  struct EV_IO *io_data = (struct EV_IO *)io->data;
  if (revents & EV_READ) {
    rb_funcall(io_data->readable_callback, ID_CALL, 0);
  }

  if (revents & EV_WRITE) {
    rb_funcall(io_data->writable_callback, ID_CALL, 0);
  }
}

static VALUE EV_IO_start(VALUE self)
{
  struct EV_IO *io;
  Data_Get_Struct(self, struct EV_IO, io);

  ev_io_start(EV_DEFAULT, &io->ev_io);

  return Qnil;
}

static VALUE EV_IO_stop(VALUE self)
{
  struct EV_IO *io;
  Data_Get_Struct(self, struct EV_IO, io);

  ev_io_stop(EV_DEFAULT, &io->ev_io);

  return Qnil;
}

static VALUE EV_IO_event_mask(VALUE self)
{
  return rb_ivar_get(self, rb_intern("event_mask"));
}

static VALUE EV_IO_set_event_mask(VALUE self, VALUE sym)
{
  if(NIL_P(sym)) {
      EV_IO_update_event_mask(self, 0);
  } else {
      EV_IO_update_event_mask(self, EV_IO_symbol2event_mask(sym));
  }

  return rb_ivar_get(self, rb_intern("event_mask"));
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

static void EV_IO_update_event_mask(VALUE self, int event_mask)
{
  ID sym_id;
  struct EV_IO *watcher;
  Data_Get_Struct(self, struct EV_IO, watcher);

  if(event_mask) {
    switch(event_mask) {
      case EV_READ:
        sym_id = ID_R;
        break;
      case EV_WRITE:
        sym_id = ID_W;
        break;
      case EV_READ | EV_WRITE:
        sym_id = ID_RW;
        break;
      default:
        rb_raise(rb_eRuntimeError, "bogus EV_IO_update_event_mask! (%d)", event_mask);
    }

    rb_ivar_set(self, rb_intern("event_mask"), ID2SYM(sym_id));
  } else {
    rb_ivar_set(self, rb_intern("event_mask"), Qnil);
  }

  if(watcher->event_mask != event_mask) {
    // If the watcher currently has an event mask, we should stop it.
    if(watcher->event_mask) {
      ev_io_stop(EV_DEFAULT, &watcher->ev_io);
    }

    // Assign the event mask we are now watching for:
    watcher->event_mask = event_mask;
    ev_io_set(&watcher->ev_io, watcher->ev_io.fd, watcher->event_mask);

    // If we are interested in events, schedule the watcher back into the event loop:
    if(watcher->event_mask) {
      ev_io_start(EV_DEFAULT, &watcher->ev_io);
    }
  }
}
