# frozen_string_literal: true

require 'rubygems'
require 'mkmf'

dir_config 'polyphony_ext'

KERNEL_INFO_RE = /Linux (\d)\.(\d+)(?:\.)?((?:\d+\.?)*)(?:\-)?([\w\-]+)?/
def get_config
  config = { linux: !!(RUBY_PLATFORM =~ /linux/) }
  return config if !config[:linux]

  kernel_info = `uname -sr`
  m = kernel_info.match(KERNEL_INFO_RE)
  raise "Could not parse Linux kernel information (#{kernel_info.inspect})" if !m

  version, major_revision, distribution = m[1].to_i, m[2].to_i, m[4]

  combined_version = version.to_i * 100 + major_revision.to_i
  
  config[:kernel_version]     = combined_version
  config[:pidfd_open]         = combined_version > 503
  config[:multishot_recv]     = combined_version >= 600
  config[:multishot_recvmsg]  = combined_version >= 600
  config[:multishot_accept]   = combined_version >= 519
  config[:submit_all_flag]    = combined_version >= 518
  config[:coop_taskrun_flag]  = combined_version >= 519

  force_libev = ENV['POLYPHONY_LIBEV'] != nil
  config[:io_uring] = !force_libev && (combined_version >= 506) && (distribution != 'linuxkit')
  config
end

config = get_config
puts "Building Polyphony (\n#{config.map { |(k, v)| "  #{k}: #{v}\n"}.join})"

require_relative 'zlib_conf'

if config[:io_uring]
  liburing_path = File.expand_path('../../vendor/liburing', __dir__)
  FileUtils.cd liburing_path do
    system('./configure', exception: true)
    FileUtils.cd File.join(liburing_path, 'src') do
      system('make', 'liburing.a', exception: true)
    end
  end

  if !find_header 'liburing.h', File.join(liburing_path, 'src/include')
    raise "Couldn't find liburing.h"
  end

  if !find_library('uring', nil, File.join(liburing_path, 'src'))
    raise "Couldn't find liburing.a"
  end
end

def define_bool(name, value)
  $defs << "-D#{name}=#{value ? 1 : 0 }"
end

$defs << '-DPOLYPHONY_USE_PIDFD_OPEN' if config[:pidfd_open]
if config[:io_uring]
  $defs << "-DPOLYPHONY_BACKEND_LIBURING"
  $defs << "-DPOLYPHONY_LINUX"
  $defs << "-DPOLYPHONY_UNSET_NONBLOCK" if RUBY_VERSION =~ /^3/
  $defs << "-DHAVE_IO_URING_PREP_MULTISHOT_ACCEPT" if config[:multishot_accept]
  $defs << "-DHAVE_IO_URING_PREP_RECV_MULTISHOT" if config[:multishot_recv]
  $defs << "-DHAVE_IO_URING_PREP_RECVMSG_MULTISHOT" if config[:multishot_recvmsg]
  $defs << "-DHAVE_IORING_SETUP_SUBMIT_ALL" if config[:submit_all_flag]
  $defs << "-DHAVE_IORING_SETUP_COOP_TASKRUN" if config[:coop_taskrun_flag]
  $CFLAGS << " -Wno-pointer-arith"
else
  $defs << "-DPOLYPHONY_BACKEND_LIBEV"
  $defs << "-DPOLYPHONY_LINUX" if config[:linux]

  $defs << "-DEV_STANDALONE" # prevent libev from assuming "config.h" exists

  define_bool('EV_USE_EPOLL', have_header('sys/epoll.h'))
  define_bool('EV_USE_KQUEUE', have_header('sys/event.h') && have_header('sys/queue.h'))
  define_bool('EV_USE_LINUXAIO', have_header('linux/aio_abi.h'))
  define_bool('EV_USE_POLL', have_type('port_event_t', 'poll.h'))
  define_bool('EV_USE_PORT', have_type('port_event_t', 'port.h'))
  define_bool('EV_USE_SELECT', have_header('sys/select.h'))
  define_bool('EV_USE_IOCP', false)

  $defs << '-DHAVE_SYS_RESOURCE_H' if have_header('sys/resource.h')

  $CFLAGS << " -Wno-comment"
  $CFLAGS << " -Wno-unused-result"
  $CFLAGS << " -Wno-dangling-else"
  $CFLAGS << " -Wno-parentheses"
end

$defs << '-DPOLYPHONY_PLAYGROUND' if ENV['POLYPHONY_PLAYGROUND']

CONFIG['optflags'] << ' -fno-strict-aliasing' unless RUBY_PLATFORM =~ /mswin/

have_header('ruby/io/buffer.h')
have_func('rb_fiber_transfer')
have_func('rb_io_path')
have_func('rb_io_descriptor')
have_func('rb_io_get_write_io')
have_func('rb_io_closed_p')
have_func('rb_io_open_descriptor')

create_makefile 'polyphony_ext'
