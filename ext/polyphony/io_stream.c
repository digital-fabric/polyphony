#include "polyphony.h"
#include "buffers.h"
#include "io_stream.h"

typedef struct io_stream {
  VALUE io;
  
  buffer_descriptor *head;
  buffer_descriptor *tail;

  buffer_descriptor *cursor_desc;
  unsigned int cursor_pos;

  int eof;
} IOStream_t;

VALUE cIOStream = Qnil;

static void IOStream_mark(void *ptr)
{
  IOStream_t *io_stream = ptr;
  rb_gc_mark(io_stream->io);
  buffer_descriptor *desc = io_stream->head;
  while (desc) {
    if (desc->type == BT_STRING) rb_gc_mark(desc->str);
    desc = desc->next;
  }
}

void io_stream_dispose(IOStream_t *io_stream)
{
  buffer_descriptor *desc = io_stream->head;

  while (desc) {
    buffer_descriptor *next = desc->next;
    bm_release(desc);
    desc = next;
  }
}

static void IOStream_free(void *ptr)
{
  IOStream_t *io_stream = ptr;

  io_stream_dispose(io_stream);
  xfree(ptr);
}

static size_t IOStream_size(const void *ptr)
{
  return sizeof(IOStream_t);
}

static const rb_data_type_t IOStream_type = {
  "IOStream",
  {IOStream_mark, IOStream_free, IOStream_size,},
  0, 0, 0
};

static VALUE IOStream_allocate(VALUE klass)
{
  IOStream_t *io_stream;

  io_stream = ALLOC(IOStream_t);
  return TypedData_Wrap_Struct(klass, &IOStream_type, io_stream);
}

static VALUE IOStream_initialize(VALUE self, VALUE io)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  io_stream->io = io;
  io_stream->head = NULL;
  io_stream->tail = NULL;
  io_stream->cursor_desc = NULL;
  io_stream->cursor_pos = 0;
  io_stream->eof = 0;

  return self;
}

VALUE IOStream_left(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  int left = 0;
  buffer_descriptor *desc = io_stream->cursor_desc;
  while (desc) {
    left += desc->len;
    desc = desc->next;
  }

  return INT2FIX(left);
}

inline void io_stream_push_desc(IOStream_t *io_stream, buffer_descriptor *desc)
{
  if (io_stream->tail) {
    io_stream->tail->next = desc;
    desc->prev = io_stream->tail;
    io_stream->tail = desc;
  }
  else {
    io_stream->head = desc;
    io_stream->tail = desc;
    io_stream->cursor_desc = desc;
    io_stream->cursor_pos = 0;
    desc->prev = NULL;
    desc->next = NULL;
  }
}

VALUE IOStream_push_string(VALUE self, VALUE str)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);
  buffer_descriptor *desc;

  // do not add empty string
  if (RSTRING_LEN(str) == 0) return self;

  if (bm_buffer_from_string(&desc, str))
    rb_raise(rb_eRuntimeError, "Failed to create buffer from given string");

  io_stream_push_desc(io_stream, desc);
  return self;
}

static inline void io_stream_fill_from_io(IOStream_t *io_stream, int min_len) {
  while (min_len > 0) {
    buffer_descriptor *desc;
    int read;

    if (bm_prep_buffer(&desc, BT_MANAGED, 8192))
      rb_raise(rb_eRuntimeError, "Failed to prepare managed buffer");

    VALUE result = Polyphony_stream_read(io_stream->io, desc, 8192, &read);
    if (IS_EXCEPTION(result)) {
      bm_release(desc);
      RAISE_EXCEPTION(result);
    }

    if (read < 0)
      rb_syserr_fail(-read, strerror(-read));
    if (!read) {
      bm_release(desc);
      io_stream->eof = true;
      return;
    }

    io_stream_push_desc(io_stream, desc);

    if (read >= min_len) return;
    min_len -= read;
  }
}

static inline int io_stream_eof_p(IOStream_t *io_stream)
{
  return io_stream->eof &&
    (!io_stream->cursor_desc || io_stream->cursor_pos >= io_stream->cursor_desc->len);
}

static inline int io_stream_prep_for_reading(IOStream_t *io_stream, int min_len)
{
  if (io_stream_eof_p(io_stream)) return -1;
  buffer_descriptor *desc = io_stream->cursor_desc;
  while (desc && (min_len > 0)) {
    int left = io_stream->cursor_desc->len - io_stream->cursor_pos;
    if (left >= min_len)
      return 0;
    else {
      min_len -= left;
      desc = desc->next;
    }
  }
  if (!io_stream->eof)
    io_stream_fill_from_io(io_stream, min_len);
  return io_stream_eof_p(io_stream);
}

static inline void io_stream_cursor_advance(IOStream_t *io_stream)
{
  if (io_stream->cursor_desc) {
    io_stream->cursor_desc->prev = io_stream->cursor_desc->next = NULL;
  }
  io_stream->cursor_desc = io_stream->cursor_desc->next;
  io_stream->cursor_pos = 0;
  if (!io_stream->cursor_desc) {
    io_stream->head = io_stream->tail = NULL;
  }
}

VALUE IOStream_getbyte(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  if (io_stream_prep_for_reading(io_stream, 1)) goto eof;

  int byte = io_stream->cursor_desc->ptr[io_stream->cursor_pos];
  io_stream->cursor_pos++;
  if (io_stream->cursor_pos == io_stream->cursor_desc->len)
    io_stream_cursor_advance(io_stream);

  return INT2FIX(byte);
eof:
  return Qnil;
}

VALUE IOStream_getc(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  if (io_stream_prep_for_reading(io_stream, 1)) goto eof;

  // TODO: add support for multi-byte chars
  VALUE chr = rb_str_new(io_stream->cursor_desc->ptr + io_stream->cursor_pos, 1);
  io_stream->cursor_pos++;
  if (io_stream->cursor_pos == io_stream->cursor_desc->len)
    io_stream_cursor_advance(io_stream);

  return chr;
eof:
  return Qnil;
}

VALUE IOStream_readpartial(int argc, VALUE *argv, VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);
  VALUE maxlen;
  VALUE buf = Qnil;

  rb_scan_args(argc, argv, "11", &maxlen, &buf);
  size_t maxlen_i = FIX2INT(maxlen);

  if (buf == Qnil)
    buf = rb_str_new(0, maxlen_i);
  rb_str_modify(buf);
  if (rb_str_capacity(buf) < maxlen_i)
    rb_str_resize(buf, maxlen_i);

  if (io_stream_prep_for_reading(io_stream, maxlen_i)) goto eof;

  char *ptr = RSTRING_PTR(buf);
  size_t total = 0;
  while (maxlen_i) {
    char *src = io_stream->cursor_desc->ptr + io_stream->cursor_pos;
    size_t len = io_stream->cursor_desc->len - io_stream->cursor_pos;
    if (len > maxlen_i) len = maxlen_i;
    memcpy(ptr, src, len);
    total += len;
    maxlen_i -= len;
    if (io_stream->cursor_pos + len < io_stream->cursor_desc->len)
      io_stream->cursor_pos += len;
    else {
      io_stream->cursor_desc = io_stream->cursor_desc->next;
      io_stream->cursor_pos = 0;
      if (!io_stream->cursor_desc) break;
    }
  }
  rb_str_set_len(buf, total);
  return buf;
eof:
  rb_raise(rb_eEOFError, "End of file");
}

VALUE IOStream_to_a(VALUE self, VALUE all)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);
  int from_cursor = !RTEST(all);
  buffer_descriptor *desc = from_cursor ? io_stream->cursor_desc : io_stream->head;
  VALUE array = rb_ary_new();

  while (desc) {
    VALUE str;
    if (from_cursor) {
      int pos = io_stream->cursor_pos;
      from_cursor = 0;
      str = rb_str_new(desc->ptr + pos, desc->len - pos);
    }
    else
      str = rb_str_new(desc->ptr, desc->len);
    
    rb_ary_push(array, str);
    desc = desc->next;
  }
  RB_GC_GUARD(array);
  return array;
}

VALUE IOStream_reset(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  io_stream_dispose(io_stream);
  io_stream->head = io_stream->tail = io_stream->cursor_desc = NULL;
  io_stream->cursor_pos = 0;
  return self;
}

VALUE IOStream_rewind(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  io_stream->cursor_desc = io_stream->head;
  io_stream->cursor_pos = 0;
  return self;
}

void io_stream_seek_forward(IOStream_t *io_stream, int ofs)
{
  while (ofs > 0) {
    if (!io_stream->cursor_desc) {
      return;
    }
    
    int left = io_stream->cursor_desc->len - io_stream->cursor_pos;
    if (left > ofs) {
      io_stream->cursor_pos += ofs;
      return;
    }
    else {
      ofs -= left;
      io_stream->cursor_desc = io_stream->cursor_desc->next;
      io_stream->cursor_pos = 0;
      if (!io_stream->cursor_desc)
        return;
    }
  }
}

void io_stream_seek_backward(IOStream_t *io_stream, int ofs)
{
  if (!io_stream->cursor_desc && io_stream->tail) {
    io_stream->cursor_desc = io_stream->tail;
    io_stream->cursor_pos = io_stream->cursor_desc->len;
  }

  while (ofs > 0) {
    if (!io_stream->cursor_desc) return;
    
    int left = io_stream->cursor_pos;
    if (left >= ofs) {
      io_stream->cursor_pos -= ofs;
      return;
    }
    else {
      ofs -= left;
      buffer_descriptor *prev = io_stream->cursor_desc->prev;
      if (prev) {
        io_stream->cursor_desc = io_stream->cursor_desc->prev;
        io_stream->cursor_pos = io_stream->cursor_desc->len;
      }
      else {
        io_stream->cursor_pos = 0;
        return;
      }
    }
  }
}

VALUE IOStream_seek(VALUE self, VALUE ofs)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);
  int ofs_i = FIX2INT(ofs);

  if (ofs_i > 0) io_stream_seek_forward(io_stream, ofs_i);
  if (ofs_i < 0) io_stream_seek_backward(io_stream, -ofs_i);
  return self;
}

VALUE IO_eof_p(VALUE self)
{
  IOStream_t *io_stream = RTYPEDDATA_DATA(self);

  if (!io_stream->eof) return Qfalse;
  if (io_stream->cursor_desc && io_stream->cursor_pos < io_stream->cursor_desc->len) return Qfalse;

  return Qtrue;
}

void Init_IOStream(void) {
  cIOStream = rb_define_class_under(mPolyphony, "IOStream", rb_cObject);
  rb_define_alloc_func(cIOStream, IOStream_allocate);

  rb_define_method(cIOStream, "initialize", IOStream_initialize, 1);
  rb_define_method(cIOStream, "left", IOStream_left, 0);
  rb_define_method(cIOStream, "<<", IOStream_push_string, 1);
  rb_define_method(cIOStream, "to_a", IOStream_to_a, 1);
  rb_define_method(cIOStream, "reset", IOStream_reset, 0);
  rb_define_method(cIOStream, "rewind", IOStream_rewind, 0);
  rb_define_method(cIOStream, "seek", IOStream_seek, 1);
  rb_define_method(cIOStream, "eof?", IO_eof_p, 0);

  rb_define_method(cIOStream, "getbyte", IOStream_getbyte, 0);
  rb_define_method(cIOStream, "getc", IOStream_getc, 0);
  
  rb_define_method(cIOStream, "readpartial", IOStream_readpartial, -1);
}
