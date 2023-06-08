# frozen_string_literal: true

require_relative 'helper'
require 'msgpack'

class IOTest < MiniTest::Test
  def setup
    super
    @i, @o = IO.pipe
  end

  def test_that_io_op_yields_to_other_fibers
    count = 0
    msg = nil
    [
      spin do
        @o.write('hello')
        @o.close
      end,

      spin do
        while count < 5
          sleep 0.01
          count += 1
        end
      end,

      spin { msg = @i.read }
    ].each(&:await)
    assert_equal 5, count
    assert_equal 'hello', msg
  end

  def test_write_multiple_arguments
    i, o = IO.pipe
    count = o.write('a', 'b', "\n", 'c')
    assert_equal 4, count
    o.close
    assert_equal "ab\nc", i.read
  end

  def test_that_double_chevron_method_returns_io
    assert_equal @o, @o << 'foo'

    @o << 'bar' << 'baz'
    @o.close
    assert_equal 'foobarbaz', @i.read
  end

  def test_wait_io
    results = []
    i, o = IO.pipe
    f = spin do
      loop do
        result = i.orig_read_nonblock(8192, exception: false)
        results << result
        case result
        when :wait_readable
          Thread.current.backend.wait_io(i, false)
        else
          break result
        end
      end
    end

    snooze
    o.write('foo')
    o.close

    result = f.await

    assert_equal 'foo', f.await
    assert_equal [:wait_readable, 'foo'], results
  end

  def test_read
    i, o = IO.pipe

    o << 'hi'
    assert_equal 'hi', i.read(2)

    o << 'foobarbaz'
    assert_equal 'foo', i.read(3)
    assert_equal 'bar', i.read(3)

    buf = +'abc'
    assert_equal 'baz', i.read(3, buf)
    assert_equal 'baz', buf

    buf = +'def'
    o << 'foobar'
    assert_equal 'deffoobar', i.read(6, buf, -1)
    assert_equal 'deffoobar', buf
  end

  def test_read_zero
    i, o = IO.pipe

    o << 'hi'
    assert_equal '', i.read(0)
  end

  def test_readpartial
    i, o = IO.pipe

    o << 'hi'
    assert_equal 'hi', i.readpartial(3)

    o << 'hi'
    assert_equal 'h', i.readpartial(1)
    assert_equal 'i', i.readpartial(1)

    spin {
      sleep 0.01
      o << 'hi'
    }
    assert_equal 'hi', i.readpartial(2)
    o.close

    assert_raises(EOFError) { i.readpartial(1) }
  end

  def test_gets
    i, o = IO.pipe

    buf = []
    f = spin do
      peer = receive
      while (l = i.gets)
        buf << l
        peer << true
      end
    end

    snooze
    assert_equal [], buf

    o << 'fab'
    f << Fiber.current
    sleep 0.05
    assert_equal [], buf

    o << "ulous\n"
    receive
    assert_equal ["fabulous\n"], buf

    o.close
    f.await
    assert_equal ["fabulous\n"], buf
  end

  def test_getc
    i, o = IO.pipe

    buf = []
    f = spin do
      while (c = i.getc)
        buf << c
      end
    end

    snooze
    assert_equal [], buf

    o << 'f'
    snooze
    o << 'g'
    o.close
    f.await
    assert_equal ['f', 'g'], buf
  end

  def test_getbyte
    i, o = IO.pipe

    buf = []
    f = spin do
      while (b = i.getbyte)
        buf << b
      end
    end

    snooze
    assert_equal [], buf

    o << 'f'
    snooze
    o << 'g'
    o.close
    f.await
    assert_equal [102, 103], buf
  end

  # see https://github.com/digital-fabric/polyphony/issues/30
  def test_reopened_tempfile
    file = Tempfile.new
    file << 'hello: world'
    file.close

    buf = nil
    File.open(file, 'r:bom|utf-8') do |f|
      buf = f.read(16384)
    end

    assert_equal 'hello: world', buf
  end

  def test_feed_loop_with_block
    i, o = IO.pipe
    unpacker = MessagePack::Unpacker.new
    buffer = []
    reader = spin do
      i.feed_loop(unpacker, :feed_each) { |msg| buffer << msg }
    end
    o << 'foo'.to_msgpack
    sleep 0.01
    assert_equal ['foo'], buffer

    o << 'bar'.to_msgpack
    sleep 0.01
    assert_equal ['foo', 'bar'], buffer

    o << 'baz'.to_msgpack
    sleep 0.01
    assert_equal ['foo', 'bar', 'baz'], buffer
  end

  class Receiver1
    attr_reader :buffer

    def initialize
      @buffer = []
    end

    def recv(obj)
      @buffer << obj
    end
  end

  def test_feed_loop_without_block
    i, o = IO.pipe
    receiver = Receiver1.new
    reader = spin do
      i.feed_loop(receiver, :recv)
    end
    o << 'foo'
    sleep 0.01
    assert_equal ['foo'], receiver.buffer

    o << 'bar'
    sleep 0.01
    assert_equal ['foo', 'bar'], receiver.buffer

    o << 'baz'
    sleep 0.01
    assert_equal ['foo', 'bar', 'baz'], receiver.buffer
  end

  class Receiver2
    attr_reader :buffer

    def initialize
      @buffer = []
    end

    def call(obj)
      @buffer << obj
    end
  end

  def test_feed_loop_without_method
    i, o = IO.pipe
    receiver = Receiver2.new
    reader = spin do
      i.feed_loop(receiver)
    end
    o << 'foo'
    sleep 0.01
    assert_equal ['foo'], receiver.buffer

    o << 'bar'
    sleep 0.01
    assert_equal ['foo', 'bar'], receiver.buffer

    o << 'baz'
    sleep 0.01
    assert_equal ['foo', 'bar', 'baz'], receiver.buffer
  end

  def test_splice_from
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe
    len = nil

    spin {
      len = o2.splice_from(i1, 1000)
      o2.close
    }

    o1.write('foobar')
    result = i2.read

    assert_equal 'foobar', result
    assert_equal 6, len
  end

  def test_splice_class_method
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe
    len = nil

    spin {
      len = IO.splice(i1, o2, 1000)
      o2.close
    }

    o1.write('foobar')
    result = i2.read

    assert_equal 'foobar', result
    assert_equal 6, len
  end

  def test_splice_class_method_with_eof_detection
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe
    splice_lens = []

    spin {
      loop {
        len = IO.splice(i1, o2, 1000)
        splice_lens << len
        break if len == 0
      }
      
      o2.close
    }

    o1.write('foobar')
    snooze
    o1.close

    result = i2.read
    assert_equal 'foobar', result
    assert_equal [6, 0], splice_lens
  end

  def test_splice_from_to_eof
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe
    len = nil


    f = spin {
      len = o2.splice_from(i1, -1000)
      o2.close
    }

    o1.write('foo')
    result = i2.readpartial(1000)
    assert_equal 'foo', result

    o1.write('bar')
    result = i2.readpartial(1000)
    assert_equal 'bar', result
    o1.close
    f.await
    assert_equal 6, len
  ensure
    if f.alive?
      f.interrupt
      f.await
    end
  end

  def test_splice_class_method_to_eof
    i1, o1 = IO.pipe
    i2, o2 = IO.pipe
    len = nil

    f = spin {
      len = IO.splice(i1, o2, -1000)
      o2.close
    }

    o1.write('foo')
    result = i2.readpartial(1000)
    assert_equal 'foo', result

    o1.write('bar')
    result = i2.readpartial(1000)
    assert_equal 'bar', result
    o1.close
    f.await
    assert_equal 6, len
  ensure
    if f.alive?
      f.interrupt
      f.await
    end
  end

  def test_double_splice
    if Thread.current.backend.kind != :io_uring
      skip "IO.double_splice available only on io_uring backend"
    end

    src = Polyphony.pipe
    dest = Polyphony.pipe
    ret = nil
    data = 'foobar' * 10

    f1 = spin {
      ret = IO.double_splice(src, dest)
      dest.close
    }

    src << data
    src.close

    f1.await

    spliced = dest.read
    assert_equal data, spliced
    assert_equal data.bytesize, ret
  end

  def test_tee_from
    skip "tested only on Linux" unless RUBY_PLATFORM =~ /linux/

    src = Polyphony.pipe
    dest1 = Polyphony.pipe
    dest2 = Polyphony.pipe

    len1 = len2 = nil

    spin {
      len1 = dest1.tee_from(src, 1000)
      dest1.close
      len2 = IO.splice(src, dest2, 1000)
      dest2.close
    }

    src << 'foobar'
    src.close
    result1 = dest1.read
    result2 = dest2.read

    assert_equal 'foobar', result1
    assert_equal 6, len1

    assert_equal 'foobar', result2
    assert_equal 6, len2
  end

  def test_tee_class_method
    skip "tested only on Linux" unless RUBY_PLATFORM =~ /linux/

    src = Polyphony.pipe
    dest1 = Polyphony.pipe
    dest2 = Polyphony.pipe

    len1 = len2 = nil

    spin {
      len1 = IO.tee(src, dest1, 1000)
      dest1.close
      len2 = IO.splice(src, dest2, 1000)
      dest2.close
    }

    src << 'foobar'
    src.close
    result1 = dest1.read
    result2 = dest2.read

    assert_equal 'foobar', result1
    assert_equal 6, len1

    assert_equal 'foobar', result2
    assert_equal 6, len2
  end



end

class IOWithRawBufferTest < MiniTest::Test
  def setup
    super
    @i, @o = IO.pipe
  end

  def test_write_with_raw_buffer
    Polyphony.__with_raw_buffer__(64) do |b|
      Polyphony.__raw_buffer_set__(b, 'foobar')
      @o << b
      @o.close
    end

    str = @i.read
    assert_equal 'foobar', str
  end

  def test_read_with_raw_buffer
    @o << '*' * 65
    @o.close
    chunks = []
    Polyphony.__with_raw_buffer__(64) do |b|
      res = @i.read(64, b)
      assert_equal 64, res
      chunks << Polyphony.__raw_buffer_get__(b, res)

      res = @i.read(64, b)
      assert_equal 1, res
      assert_equal 64, Polyphony.__raw_buffer_size__(b)
      chunks << Polyphony.__raw_buffer_get__(b, res)
    end
    assert_equal ['*' * 64, '*'], chunks
  end
end

class IOClassMethodsTest < MiniTest::Test
  def test_binread
    s = IO.binread(__FILE__)
    assert_kind_of String, s
    assert !s.empty?
    assert_equal IO.orig_binread(__FILE__), s

    s = IO.binread(__FILE__, 100)
    assert_equal 100, s.bytesize
    assert_equal IO.orig_binread(__FILE__, 100), s

    s = IO.binread(__FILE__, 100, 2)
    assert_equal 100, s.bytesize
    assert_equal 'frozen', s[0..5]
  end

  BIN_DATA = "\x00\x01\x02\x03"

  def test_binwrite
    fn = '/tmp/test_binwrite'
    FileUtils.rm(fn) rescue nil

    len = IO.binwrite(fn, BIN_DATA)
    assert_equal 4, len
    s = IO.binread(fn)
    assert_equal BIN_DATA, s
  end

  def test_foreach
    lines = []
    IO.foreach(__FILE__) { |l| lines << l }
    assert_equal "# frozen_string_literal: true\n", lines[0]
    assert_equal "end\n", lines[-1]
  end

  def test_read_class_method
    s = IO.read(__FILE__)
    assert_kind_of String, s
    assert(!s.empty?)
    assert_equal IO.orig_read(__FILE__), s

    s = IO.read(__FILE__, 100)
    assert_equal 100, s.bytesize
    assert_equal IO.orig_read(__FILE__, 100), s

    s = IO.read(__FILE__, 100, 2)
    assert_equal 100, s.bytesize
    assert_equal 'frozen', s[0..5]
  end

  def test_readlines
    lines = IO.readlines(__FILE__)
    assert_equal "# frozen_string_literal: true\n", lines[0]
    assert_equal "end\n", lines[-1]
  end

  WRITE_DATA = "foo\nbar קוקו"

  def test_write_class_method
    fn = '/tmp/test_write'
    FileUtils.rm(fn) rescue nil

    len = IO.write(fn, WRITE_DATA)
    assert_equal WRITE_DATA.bytesize, len
    s = IO.read(fn)
    assert_equal WRITE_DATA, s
  end

  def test_popen
    skip unless IS_LINUX

    counter = 0
    timer = spin { throttled_loop(20) { counter += 1 } }

    IO.popen('sleep 0.5') { |io| io.read(8192) }
    assert(counter >= 5)

    result = nil
    IO.popen('echo "foo"') { |io| result = io.read(8192) }
    assert_equal "foo\n", result
  ensure
    timer&.stop
  end

  def test_kernel_gets
    counter = 0
    timer = spin { throttled_loop(200) { counter += 1 } }

    i, o = IO.pipe
    orig_stdin = $stdin
    $stdin = i
    spin do
      sleep 0.01
      o.puts 'foo'
      o.close
    end

    assert(counter >= 0)
    assert_equal "foo\n", gets
  ensure
    $stdin = orig_stdin
    timer&.stop
  end

  def test_kernel_gets_with_argv
    ARGV << __FILE__

    s = StringIO.new(IO.orig_read(__FILE__))

    while (l = s.gets)
      assert_equal l, gets
    end
  ensure
    ARGV.delete __FILE__
  end

  def test_kernel_puts
    orig_stdout = $stdout
    o = eg(
      '@buf': +'',
      write:  ->(*args) { args.each { |a| @buf << a } },
      flush:  -> {},
      buf:    -> { @buf }
    )

    $stdout = o

    puts 'foobar'
    assert_equal "foobar\n", o.buf
  ensure
    $stdout = orig_stdout
  end

  def test_read_large_file
    fn = '/tmp/test.txt'
    File.open(fn, 'w') { |f| f << ('*' * 1e6) }
    s = IO.read(fn)
    assert_equal 1e6, s.bytesize
    assert s == IO.orig_read(fn)
  end

  def pipe_read
    i, o = IO.pipe
    yield o
    o.close
    i.read
  ensure
    i.close
  end

  def test_puts
    assert_equal "foo\n", pipe_read { |f| f.puts 'foo' }
    assert_equal "foo\n", pipe_read { |f| f.puts "foo\n" }
    assert_equal "foo\nbar\n", pipe_read { |f| f.puts 'foo', 'bar' }
    assert_equal "foo\nbar\n", pipe_read { |f| f.puts 'foo', "bar\n" }
  end

  def test_read_loop
    i, o = IO.pipe

    buf = []
    f = spin do
      buf << :ready
      i.read_loop { |d| buf << d }
      buf << :done
    end

    # writing always causes snoozing
    o << 'foo'
    3.times { snooze }
    o << 'bar'
    o.close

    f.await
    assert_equal [:ready, 'foo', 'bar', :done], buf
  end

  def test_read_loop_break
    i, o = IO.pipe

    buf = []
    f = spin do
      buf << :ready
      i.read_loop do |d|
        buf << d
        break if d == 'bar'
      end
      buf << :done
    end

    # writing always causes snoozing
    o << 'foo'
    3.times { snooze }
    o << 'bar'
    f.await
    assert_equal [:ready, 'foo', 'bar', :done], buf
  end

  def test_read_loop_with_max_len
    r, w = IO.pipe

    w << 'foobar'
    w.close
    buf = []
    r.read_loop(3) { |data| buf << data }
    assert_equal ['foo', 'bar'], buf
  end
end

class IOExtensionsTest < MiniTest::Test
  def test_deflate
    i, o = IO.pipe
    r, w = IO.pipe

    ret = nil
    f = spin {
      ret = IO.deflate(i, w)
      w.close
    }

    o << 'foobar' * 20
    o.close

    f.await
    assert_equal 17, ret

    data = r.read
    msg = Zlib::Inflate.inflate(data)
    assert_equal 'foobar' * 20, msg
  end

  def test_deflate_to_string
    i, o = IO.pipe
    r, w = IO.pipe
    str = +''

    ret = nil
    f = spin {
      ret = IO.deflate(i, str)
      w << str
      w.close
    }

    o << 'foobar' * 20
    o.close

    f.await
    assert_equal 17, ret

    data = r.read
    msg = Zlib::Inflate.inflate(data)
    assert_equal 'foobar' * 20, msg
  end

  def test_deflate_to_frozen_string
    i, o = IO.pipe
    str = '' # frozen

    f = spin {
      o << 'foobar' * 20
      o.close
    }

    assert_raises(FrozenError) { IO.deflate(i, str) }
  end

  def test_deflate_from_string
    r, w = IO.pipe
    str = 'foobar' * 10000
    ret = nil

    f = spin {
      ret = IO.deflate(str, w)
      w.close
    }
    f.await
    assert_equal 118, ret

    data = r.read
    msg = Zlib::Inflate.inflate(data)
    assert_equal str, msg
  end

  def test_inflate
    i, o = IO.pipe
    r, w = IO.pipe

    spin {
      data = Zlib::Deflate.deflate('foobar', 9)
      o << data
      o.close
    }

    ret = IO.inflate(i, w)
    assert_equal 6, ret
    w.close
    msg = r.read
    assert_equal 'foobar', msg
  end

  def test_inflate_to_string
    i, o = IO.pipe
    str = +''

    spin {
      data = Zlib::Deflate.deflate('foobar', 9)
      o << data
      o.close
    }

    ret = IO.inflate(i, str)
    assert_equal 6, ret
    assert_equal 6, str.bytesize
    assert_equal 'foobar', str
  end

  def test_inflate_from_string
    r, w = IO.pipe
    str = Zlib::Deflate.deflate('foobar', 9)

    ret = IO.inflate(str, w)
    assert_equal 6, ret
    w.close
    msg = r.read
    assert_equal 'foobar', msg
  end

  def test_gzip
    src = Polyphony.pipe
    dest = Polyphony.pipe
    now = nil

    f = spin {
      now = Time.now
      IO.gzip(src, dest)
      dest.close
    }

    src << IO.read(__FILE__)
    src.close
    f.await

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
    assert_in_range (now-2)..(now+1), gz.mtime
    assert_nil gz.orig_name
    assert_nil gz.comment
  end

  def test_gzip_to_string
    src = Polyphony.pipe
    dest = Polyphony.pipe
    str = +''
    now = nil

    f = spin {
      now = Time.now
      IO.gzip(src, str)
      dest << str
      dest.close
    }

    src << IO.read(__FILE__)
    src.close
    f.await

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
    assert_in_range (now-2)..(now+1), gz.mtime
    assert_nil gz.orig_name
    assert_nil gz.comment
  end

  def test_gzip_from_string
    str = IO.read(__FILE__)
    dest = Polyphony.pipe
    now = nil

    IO.gzip(str, dest)
    dest.close

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
  end

  def test_gzip_return_value
    src = Polyphony.pipe
    dest = Polyphony.pipe
    now = nil
    ret = nil

    f = spin {
      now = Time.now
      ret = IO.gzip(src, dest)
      dest.close
    }

    src << IO.read(__FILE__)
    src.close
    f.await

    gzipped = dest.read
    assert_equal gzipped.bytesize, ret
  end

  def test_gzip_with_mtime_int
    src = Polyphony.pipe
    dest = Polyphony.pipe

    spin {
      IO.gzip(src, dest, mtime: 42)
      dest.close
    }

    src << IO.read(__FILE__)
    src.close

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
    assert_equal Time.at(42), gz.mtime
  end

  def test_gzip_with_mtime_false
    src = Polyphony.pipe
    dest = Polyphony.pipe

    spin {
      IO.gzip(src, dest, mtime: false)
      dest.close
    }

    src << IO.read(__FILE__)
    src.close

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
    assert_equal Time.at(0), gz.mtime
  end

  def test_gzip_with_mtime_time
    src = Polyphony.pipe
    dest = Polyphony.pipe
    t = Time.at(Time.now.to_i) - rand(300000)

    spin {
      IO.gzip(src, dest, mtime: t)
      dest.close
    }

    src << IO.read(__FILE__)
    src.close

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
    assert_equal t, gz.mtime
  end

  def test_gzip_with_orig_name
    src = Polyphony.pipe
    dest = Polyphony.pipe

    spin {
      IO.gzip(src, dest, orig_name: '/foo/bar')
      dest.close
    }

    src << IO.read(__FILE__)
    src.close

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
    assert_equal '/foo/bar', gz.orig_name
  end

  def test_gzip_with_comment
    src = Polyphony.pipe
    dest = Polyphony.pipe

    spin {
      IO.gzip(src, dest, comment: 'hello!')
      dest.close
    }

    src << IO.read(__FILE__)
    src.close

    gz = Zlib::GzipReader.new(dest)
    data = gz.read
    assert_equal IO.read(__FILE__), data
    assert_equal 'hello!', gz.comment
  end

  def test_gunzip
    src = Polyphony.pipe
    dest = Polyphony.pipe
    ret = nil

    f = spin {
      ret = IO.gunzip(src, dest)
      dest.close
    }

    gz = Zlib::GzipWriter.new(src, 9)
    gz << IO.read(__FILE__)
    gz.close
    f.await

    data = dest.read
    assert_equal IO.read(__FILE__).bytesize, ret
    assert_equal IO.read(__FILE__), data
  end

  def test_gunzip_to_string
    src = Polyphony.pipe
    str = +''
    ret = nil

    f = spin {
      ret = IO.gunzip(src, str)
    }

    gz = Zlib::GzipWriter.new(src, 9)
    gz << IO.read(__FILE__)
    gz.close
    f.await

    assert_equal IO.read(__FILE__).bytesize, ret
    assert_equal IO.read(__FILE__), str
  end

  def test_gunzip_from_string
    src_data = 'foobar' * 1000
    str = Zlib.gzip(src_data, level: 9)
    dest = Polyphony.pipe
    ret = IO.gunzip(str, dest)
    dest.close

    dest_data = dest.read
    assert_equal src_data.bytesize, ret
    assert_equal src_data, dest_data
  end

  def test_gunzip_multi
    src1 = Polyphony.pipe
    src2 = Polyphony.pipe
    dest = Polyphony.pipe

    spin {
      IO.gunzip(src1, dest)
      IO.gunzip(src2, dest)
      dest.close
    }

    gz1 = Zlib::GzipWriter.new(src1)
    gz1 << 'foobar'
    gz1.close

    gz1 = Zlib::GzipWriter.new(src2)
    gz1 << 'raboof'
    gz1.close

    data = dest.read
    assert_equal 'foobarraboof', data
  end

  def test_gzip_gunzip
    gzipped = Polyphony.pipe
    gunzipped = Polyphony.pipe

    spin { File.open(__FILE__, 'r') { |f| IO.gzip(f, gzipped) }; gzipped.close }
    spin { IO.gunzip(gzipped, gunzipped); gunzipped.close }

    data = gunzipped.read
    assert_equal IO.read(__FILE__), data
  end

  def test_gunzip_with_empty_info
    gzipped = Polyphony.pipe
    gunzipped = Polyphony.pipe
    info = {}

    spin {
      File.open(__FILE__, 'r') { |f| IO.gzip(f, gzipped, mtime: false) }
      gzipped.close
    }
    spin { IO.gunzip(gzipped, gunzipped, info); gunzipped.close }

    data = gunzipped.read
    assert_equal IO.read(__FILE__), data
    assert_equal Time.at(0), info[:mtime]
    assert_nil info[:orig_name]
    assert_nil info[:comment]
  end

  def test_gunzip_with_info
    src = Polyphony.pipe
    gzipped = Polyphony.pipe
    gunzipped = Polyphony.pipe

    src_info = {
      mtime: 42,
      orig_name: 'foo.bar',
      comment: 'hello!'
    }

    dest_info = {}

    spin { IO.gzip(src, gzipped, src_info); gzipped.close }
    spin { IO.gunzip(gzipped, gunzipped, dest_info); gunzipped.close }

    src << 'foobar'
    src.close

    data = gunzipped.read
    assert_equal 'foobar', data
    assert_equal Time.at(42), dest_info[:mtime]
    assert_equal 'foo.bar', dest_info[:orig_name]
    assert_equal 'hello!', dest_info[:comment]
  end

  def test_deflate_inflate_strings
    src_data = IO.read(__FILE__)
    deflated = +''
    IO.deflate(src_data, deflated)
    inflated = +''
    IO.inflate(deflated, inflated)

    assert_equal src_data, inflated
  end

  def test_gzip_gunzip_strings
    src_data = IO.read(__FILE__)
    gzipped = +''
    IO.gzip(src_data, gzipped)
    gunzipped = +''
    IO.gunzip(gzipped, gunzipped)

    assert_equal src_data, gunzipped
  end
end

class IOIssuesTest < MiniTest::Test
  def test_issue_93
    # Write a file with 100 lines of 100 000 characters each
    File.open('/tmp/test.gz', 'w+') do |file|
      gz = Zlib::GzipWriter.new(file)
      gz.write("#{'a' * 10_000}\n" * 1000)
      gz.close
    end

    # Read the file
    gz = Zlib::GzipReader.open('/tmp/test.gz')
    count = 0
    it = gz.each_line

    loop do
      it.next
      count += 1
    rescue StopIteration
      break
    end

    assert_equal 1000, count
  end
end
