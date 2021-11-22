# frozen_string_literal: true

require 'rubygems'
require 'mkmf'


KERNEL_INFO_RE = /Linux (\d)\.(\d+)\.(?:\d+)\-(?:\d+\-)?(\w+)/
def get_config
  config = { linux: !!(RUBY_PLATFORM =~ /linux/) }
  return config if !config[:linux]

  kernel_info = `uname -sr`
  m = kernel_info.match(KERNEL_INFO_RE)
  raise "Could not parse Linux kernel information (#{kernel_info.inspect})" if !m

  version, major_revision, distribution = m[1].to_i, m[2].to_i, m[3]
  config[:pidfd_open] = (version == 5) && (major_revision >= 3)

  force_libev = ENV['POLYPHONY_USE_LIBEV'] != nil
  config[:io_uring] = !force_libev &&
    (version == 5) && (major_revision >= 6) && (distribution != 'linuxkit')
  config
end

config = get_config
puts "Building Polyphony... (#{config.inspect})"

$defs << '-DPOLYPHONY_USE_PIDFD_OPEN' if config[:pidfd_open]
if config[:io_uring]
  $defs << "-DPOLYPHONY_BACKEND_LIBURING"
  $defs << "-DPOLYPHONY_UNSET_NONBLOCK" if RUBY_VERSION =~ /^3/
  $CFLAGS << " -Wno-pointer-arith"
else
  $defs << "-DPOLYPHONY_BACKEND_LIBEV"
  $defs << "-DPOLYPHONY_LINUX" if config[:linux]
  $defs << '-DEV_USE_LINUXAIO'     if have_header('linux/aio_abi.h')
  $defs << '-DEV_USE_SELECT'       if have_header('sys/select.h')
  $defs << '-DEV_USE_POLL'         if have_type('port_event_t', 'poll.h')
  $defs << '-DEV_USE_EPOLL'        if have_header('sys/epoll.h')
  $defs << '-DEV_USE_KQUEUE'       if have_header('sys/event.h') && have_header('sys/queue.h')
  $defs << '-DEV_USE_PORT'         if have_type('port_event_t', 'port.h')
  $defs << '-DHAVE_SYS_RESOURCE_H' if have_header('sys/resource.h')

  $CFLAGS << " -Wno-comment"
  $CFLAGS << " -Wno-unused-result"
  $CFLAGS << " -Wno-dangling-else"
  $CFLAGS << " -Wno-parentheses"
end

$defs << '-DPOLYPHONY_PLAYGROUND' if ENV['POLYPHONY_PLAYGROUND']

CONFIG['optflags'] << ' -fno-strict-aliasing' unless RUBY_PLATFORM =~ /mswin/


dir_config 'polyphony_ext'
create_makefile 'polyphony_ext'
