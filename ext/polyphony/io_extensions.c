#include <time.h>

#include "polyphony.h"
#include "zlib.h"
#include "assert.h"

ID ID_at;
ID ID_read_method;
ID ID_to_i;
ID ID_write_method;

VALUE SYM_mtime;
VALUE SYM_orig_name;
VALUE SYM_comment;

enum read_method {
  RM_BACKEND_READ,
  RM_BACKEND_RECV
};

enum write_method {
  WM_BACKEND_WRITE,
  WM_BACKEND_SEND
};

#define print_buffer(prefix, ptr, len) { \
  printf("%s buffer (%d): ", prefix, (int)len); \
  for (int i = 0; i < len; i++) printf("%02X ", ptr[i]); \
  printf("\n"); \
}

#define CHUNK 16384
#define MAX_WRITE_STR_LEN 16384
#define DEFAULT_LEVEL 9
#define DEFAULT_MEM_LEVEL 8

/* from zutil.h */
#define OS_MSDOS    0x00
#define OS_AMIGA    0x01
#define OS_VMS      0x02
#define OS_UNIX     0x03
#define OS_ATARI    0x05
#define OS_OS2      0x06
#define OS_MACOS    0x07
#define OS_TOPS20   0x0a
#define OS_WIN32    0x0b

#define OS_VMCMS    0x04
#define OS_ZSYSTEM  0x08
#define OS_CPM      0x09
#define OS_QDOS     0x0c
#define OS_RISCOS   0x0d
#define OS_UNKNOWN  0xff

#ifndef OS_CODE
#define OS_CODE  OS_UNIX
#endif

inline int read_to_raw_buffer(VALUE backend, VALUE io, enum read_method method, struct raw_buffer *buffer) {
  VALUE len = Backend_read(backend, io, PTR2FIX(buffer), Qnil, Qfalse, INT2FIX(0));
  return (len == Qnil) ? 0 : FIX2INT(len);
}

inline int write_from_raw_buffer(VALUE backend, VALUE io, enum write_method method, struct raw_buffer *buffer) {
  VALUE len = Backend_write(backend, io, PTR2FIX(buffer));
  return FIX2INT(len);
}

static inline int write_c_string_from_str(VALUE str, struct raw_buffer *buffer) {
  int strlen = RSTRING_LEN(str);
  if (strlen >= buffer->len)
    rb_raise(rb_eRuntimeError, "string too long to fit in gzip header buffer");

  memcpy(buffer->ptr, RSTRING_PTR(str), strlen);
  buffer->ptr[strlen] = 0;
  int written = strlen + 1;
  buffer->ptr += written;
  buffer->len -= written;
  return written;
}

struct gzip_header_ctx {
  VALUE mtime;
  VALUE orig_name;
  VALUE comment;
};

struct gzip_footer_ctx {
  int crc32;
  int isize;
};

#define GZ_MAGIC1             0x1f
#define GZ_MAGIC2             0x8b
#define GZ_METHOD_DEFLATE     8
#define GZ_FLAG_MULTIPART     0x2
#define GZ_FLAG_EXTRA         0x4
#define GZ_FLAG_ORIG_NAME     0x8
#define GZ_FLAG_COMMENT       0x10
#define GZ_FLAG_ENCRYPT       0x20
#define GZ_FLAG_UNKNOWN_MASK  0xc0

#define GZ_EXTRAFLAG_FAST     0x4
#define GZ_EXTRAFLAG_SLOW     0x2

static inline void gzfile_set32(unsigned long n, unsigned char *dst) {
  *(dst++) = n & 0xff;
  *(dst++) = (n >> 8) & 0xff;
  *(dst++) = (n >> 16) & 0xff;
  *dst     = (n >> 24) & 0xff;
}

static inline unsigned long gzfile_get32(unsigned char *src) {
  unsigned long n;
  n  = *(src++) & 0xff;
  n |= (*(src++) & 0xff) << 8;
  n |= (*(src++) & 0xff) << 16;
  n |= (*(src++) & 0xffU) << 24;
  return n;
}

static inline time_t time_from_object(VALUE o) {
  if (o == Qfalse) return 0;
  if (o == Qnil) return time(0); // now
  if (FIXNUM_P(o)) return FIX2INT(o);
  return FIX2INT(rb_funcall(o, rb_intern("to_i"), 0));
}

int gzip_prepare_header(struct gzip_header_ctx *ctx, char *buffer, int maxlen) {
  int len = 0;
  unsigned char flags = 0, extraflags = 0;

  assert(maxlen >= 10);

  if (!NIL_P(ctx->orig_name)) flags |= GZ_FLAG_ORIG_NAME;
  if (!NIL_P(ctx->comment))   flags |= GZ_FLAG_COMMENT;

  if (ctx->mtime)
    ctx->mtime = time_from_object(ctx->mtime);

  buffer[0] = GZ_MAGIC1;
  buffer[1] = GZ_MAGIC2;
  buffer[2] = GZ_METHOD_DEFLATE;
  buffer[3] = flags;
  gzfile_set32((unsigned long)ctx->mtime, &buffer[4]);
  buffer[8] = extraflags;
  buffer[9] = OS_CODE;

  len = 10;

  struct raw_buffer buffer_spec = {buffer + len, maxlen - len};
  if (!NIL_P(ctx->orig_name))
    len += write_c_string_from_str(ctx->orig_name, &buffer_spec);
  if (!NIL_P(ctx->comment))
    len += write_c_string_from_str(ctx->comment, &buffer_spec);

  return len;
}

int gzip_prepare_footer(unsigned long crc32, unsigned long total_in, char *buffer, int maxlen) {
  assert(maxlen >= 8);

  gzfile_set32(crc32, buffer);
  gzfile_set32(total_in, buffer + 4);

  return 8;
}

enum stream_mode {
  SM_DEFLATE,
  SM_INFLATE
};

struct z_stream_ctx {
  VALUE backend;
  VALUE src;
  VALUE dest;

  enum stream_mode mode;
  z_stream strm;

  unsigned char in[CHUNK];
  unsigned char out[CHUNK];
  int in_pos;
  int out_pos;
  unsigned long in_total;
  unsigned long out_total;

  unsigned long crc32;
};

typedef int (*zlib_func)(z_streamp, int);

void read_gzip_header_str(struct raw_buffer *buffer, VALUE *str, int *in_pos, unsigned long *total_read) {
  int null_pos;
  // find null terminator
  for (null_pos = *in_pos; null_pos < *total_read; null_pos++) {
    if (!buffer->ptr[null_pos]) break;
  }
  if (null_pos == *total_read)
    rb_raise(rb_eRuntimeError, "Invalid gzip header");
  
  *str = rb_str_new_cstr(buffer->ptr + *in_pos);
  *in_pos = null_pos + 1;
}

void gzip_read_header(struct z_stream_ctx *ctx, struct gzip_header_ctx *header_ctx) {
  struct raw_buffer in_buffer = { ctx->in, CHUNK };
  int flags;

  while (ctx->in_total < 10) {
    int read = read_to_raw_buffer(ctx->backend, ctx->src, RM_BACKEND_READ, &in_buffer);
    if (read == 0) goto error;
    ctx->in_total += read;
  }
  // print_buffer("read gzip header", ctx->in, ctx->in_total);
  if (ctx->in[0] != GZ_MAGIC1) goto error;
  if (ctx->in[1] != GZ_MAGIC2) goto error;
  if (ctx->in[2] != GZ_METHOD_DEFLATE) goto error;
  flags = ctx->in[3];

  unsigned long mtime = gzfile_get32(ctx->in + 4);
  header_ctx->mtime = INT2FIX(mtime);

  ctx->in_pos = 10;

  if (flags & GZ_FLAG_ORIG_NAME)
    read_gzip_header_str(&in_buffer, &header_ctx->orig_name, &ctx->in_pos, &ctx->in_total);
  else
    header_ctx->orig_name = Qnil;
  if (flags & GZ_FLAG_COMMENT)
    read_gzip_header_str(&in_buffer, &header_ctx->comment, &ctx->in_pos, &ctx->in_total);
  else
    header_ctx->comment = Qnil;
  return;

error:
  rb_raise(rb_eRuntimeError, "Invalid gzip header");
}

// void gzip_read_footer(struct z_stream_ctx *ctx, struct gzip_footer_ctx *footer_ctx) {  
// }

inline int z_stream_write_out(struct z_stream_ctx *ctx, zlib_func fun, int eof) {
  int ret;
  int written;
  struct raw_buffer out_buffer;

  int avail_out_pre = ctx->strm.avail_out = CHUNK - ctx->out_pos;
  ctx->strm.next_out = ctx->out + ctx->out_pos;
  ret = fun(&ctx->strm, eof ? Z_FINISH : Z_NO_FLUSH);
  assert(ret != Z_STREAM_ERROR);
  written = avail_out_pre - ctx->strm.avail_out;
  out_buffer.ptr = ctx->out;
  out_buffer.len = ctx->out_pos + written;
  if (out_buffer.len) {
    ret = write_from_raw_buffer(ctx->backend, ctx->dest, WM_BACKEND_WRITE, &out_buffer);
    if (ctx->mode == SM_INFLATE)
      ctx->crc32 = crc32(ctx->crc32, out_buffer.ptr + ctx->out_pos, written);
    ctx->out_total += ret - ctx->out_pos;
  }
  ctx->out_pos = 0;
  return ctx->strm.avail_out;
}

void z_stream_io_loop(struct z_stream_ctx *ctx) {
  zlib_func fun = (ctx->mode == SM_DEFLATE) ? deflate : inflate;  

  if (ctx->in_total > ctx->in_pos) {
    // In bytes already read for parsing gzip header, so we need to process the
    // rest.
    ctx->strm.next_in = ctx->in + ctx->in_pos;
    ctx->strm.avail_in = ctx->in_total -= ctx->in_pos;

    while (1) {
      // z_stream_write_out returns strm.avail_out. If there's still room in the
      // out buffer that means the input buffer has been exhausted.
      if (z_stream_write_out(ctx, fun, 0)) break;
    }
  }

  while (1) {
    struct raw_buffer in_buffer = {ctx->in, CHUNK};
    ctx->strm.next_in = ctx->in;
    int read_len = ctx->strm.avail_in = read_to_raw_buffer(ctx->backend, ctx->src, RM_BACKEND_READ, &in_buffer);
    if (!read_len) break;
    int eof = read_len < CHUNK;

    if (ctx->mode == SM_DEFLATE)
      ctx->crc32 = crc32(ctx->crc32, ctx->in, read_len);
    ctx->in_total += read_len;

    // print_buffer("read stream", ctx->in, read_len);

    while (1) {
      // z_stream_write_out returns strm.avail_out. If there's still room in the
      // out buffer that means the input buffer has been exhausted.
      if (z_stream_write_out(ctx, fun, eof)) break;
    }

    if (eof) return;
  }

  //flush
  ctx->strm.avail_in = 0;
  ctx->strm.next_in = ctx->in;
  z_stream_write_out(ctx, fun, 1);
}

inline void setup_ctx(struct z_stream_ctx *ctx, enum stream_mode mode, VALUE src, VALUE dest) {
  ctx->backend = BACKEND();
  ctx->src = src;
  ctx->dest = dest;
  ctx->mode = mode;
  ctx->strm.zalloc = Z_NULL;
  ctx->strm.zfree = Z_NULL;
  ctx->strm.opaque = Z_NULL;
  ctx->in_pos = 0;
  ctx->out_pos = 0;
  ctx->in_total = 0;
  ctx->out_total = 0;
  ctx->crc32 = 0;
}

VALUE IO_gzip(int argc, VALUE *argv, VALUE self) {
  VALUE src;
  VALUE dest;
  VALUE opts = Qnil;
  int opts_present;

  rb_scan_args(argc, argv, "21", &src, &dest, &opts);
  opts_present = opts != Qnil;

  struct gzip_header_ctx header_ctx = {
    opts_present ? rb_hash_aref(opts, SYM_mtime) : Qnil,
    opts_present ? rb_hash_aref(opts, SYM_orig_name) : Qnil,
    opts_present ? rb_hash_aref(opts, SYM_comment) : Qnil
  };

  struct z_stream_ctx ctx;
  int level = DEFAULT_LEVEL;
  int ret;

  setup_ctx(&ctx, SM_DEFLATE, src, dest);
  ctx.out_pos = gzip_prepare_header(&header_ctx, ctx.out, sizeof(ctx.out));

  ret = deflateInit2(&ctx.strm, level, Z_DEFLATED, -MAX_WBITS, DEFAULT_MEM_LEVEL, Z_DEFAULT_STRATEGY);
  if (ret != Z_OK) return INT2FIX(ret);
  z_stream_io_loop(&ctx);
  int footer_len = gzip_prepare_footer(ctx.crc32, ctx.in_total, ctx.out, sizeof(ctx.out));
  struct raw_buffer footer_buffer = {ctx.out, footer_len};
  write_from_raw_buffer(ctx.backend, dest, WM_BACKEND_WRITE, &footer_buffer);
  deflateEnd(&ctx.strm);
 
  return INT2FIX(ctx.out_total);
}

inline VALUE FIX2TIME(VALUE v) {
  return rb_funcall(rb_cTime, ID_at, 1, v);
}

VALUE IO_gunzip(int argc, VALUE *argv, VALUE self) {
  VALUE src;
  VALUE dest;
  VALUE info = Qnil;

  rb_scan_args(argc, argv, "21", &src, &dest, &info);

  struct gzip_header_ctx header_ctx;
  // struct gzip_footer_ctx footer_ctx;
  struct z_stream_ctx ctx;
  int ret;

  setup_ctx(&ctx, SM_INFLATE, src, dest);
  gzip_read_header(&ctx, &header_ctx);

  if (info != Qnil) {
    rb_hash_aset(info, SYM_mtime, FIX2TIME(header_ctx.mtime));
    rb_hash_aset(info, SYM_orig_name, header_ctx.orig_name);
    rb_hash_aset(info, SYM_comment, header_ctx.comment);
  }

  ret = inflateInit2(&ctx.strm, -MAX_WBITS);
  if (ret != Z_OK) return INT2FIX(ret);
  z_stream_io_loop(&ctx);
  inflateEnd(&ctx.strm);

  // gzip_read_footer(&ctx, &footer_ctx);
  // TODO: verify crc32
  // TODO: verify total length
  return self;
}

VALUE IO_deflate(VALUE self, VALUE src, VALUE dest) {
  struct z_stream_ctx ctx;
  int level = DEFAULT_LEVEL;
  int ret;

  setup_ctx(&ctx, SM_DEFLATE, src, dest);
  ret = deflateInit(&ctx.strm, level);
  if (ret != Z_OK) return INT2FIX(ret);
  z_stream_io_loop(&ctx);
  deflateEnd(&ctx.strm);
 
  return INT2FIX(ctx.out_total);
}

VALUE IO_inflate(VALUE self, VALUE src, VALUE dest) {
  struct z_stream_ctx ctx;
  int ret;

  setup_ctx(&ctx, SM_INFLATE, src, dest);
  ret = inflateInit(&ctx.strm);
  if (ret != Z_OK) return INT2FIX(ret);
  z_stream_io_loop(&ctx);
  inflateEnd(&ctx.strm);
 
  return INT2FIX(ctx.out_total);
}

void Init_IOExtensions() {
  rb_define_singleton_method(rb_cIO, "gzip", IO_gzip, -1);
  rb_define_singleton_method(rb_cIO, "gunzip", IO_gunzip, -1);
  rb_define_singleton_method(rb_cIO, "deflate", IO_deflate, 2);
  rb_define_singleton_method(rb_cIO, "inflate", IO_inflate, 2);

  ID_at           = rb_intern("at");
  ID_read_method  = rb_intern("__read_method__");
  ID_to_i         = rb_intern("to_i");
  ID_write_method = rb_intern("__write_method__");

  SYM_mtime     = ID2SYM(rb_intern("mtime"));
  SYM_orig_name = ID2SYM(rb_intern("orig_name"));
  SYM_comment   = ID2SYM(rb_intern("comment"));
}
