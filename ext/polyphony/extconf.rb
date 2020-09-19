# frozen_string_literal: true

require 'rubygems'
require 'mkmf'

use_liburing = false
force_use_libev = ENV['POLYPHONY_USE_LIBEV'] != nil

if !force_use_libev && RUBY_PLATFORM =~ /linux/ && `uname -srm` =~ /Linux (5\.\d)/
  kernel_version = $1.gsub('.', '').to_i
  $defs << "-DPOLYPHONY_KERNEL_VERSION_#{kernel_version}"
  case kernel_version
  when 55..59
    use_liburing = true
    $defs << "-DPOLYPHONY_IO_URING"
    $defs << "-DPOLYPHONY_IO_URING_ACCEPT"
    $defs << "-DPOLYPHONY_IO_URING_CONNECT"
    $defs << "-DPOLYPHONY_IO_URING_ASYNC_CANCEL"
  when 54
    use_liburing = true
    $defs << "-DPOLYPHONY_IO_URING"
    $defs << "-DPOLYPHONY_IO_URING_TIMEOUT"
  end
end

if use_liburing
  puts "Compiling liburing"
  ext_dir = File.join(FileUtils.pwd, RbConfig::CONFIG["srcdir"], '..')
  `cd #{ext_dir}/liburing && make`

  lib_dir = RbConfig::CONFIG['libdir']
  include_dir = RbConfig::CONFIG['includedir']

  header_dirs = [include_dir, File.join(ext_dir, 'liburing/src/include')]
  lib_dirs = [lib_dir, File.join(ext_dir, 'liburing/src')]
  dir_config('polyphony', header_dirs, lib_dirs)

  $defs << "-DPOLYPHONY_BACKEND_LIBURING"
else
  $defs << "-DPOLYPHONY_BACKEND_LIBEV"
end

$defs << '-DEV_USE_LINUXAIO'     if have_header('linux/aio_abi.h')
$defs << '-DEV_USE_SELECT'       if have_header('sys/select.h')
$defs << '-DEV_USE_POLL'         if have_type('port_event_t', 'poll.h')
$defs << '-DEV_USE_EPOLL'        if have_header('sys/epoll.h')
$defs << '-DEV_USE_KQUEUE'       if have_header('sys/event.h') && have_header('sys/queue.h')
$defs << '-DEV_USE_PORT'         if have_type('port_event_t', 'port.h')
$defs << '-DHAVE_SYS_RESOURCE_H' if have_header('sys/resource.h')

CONFIG['optflags'] << ' -fno-strict-aliasing' unless RUBY_PLATFORM =~ /mswin/

dir_config 'polyphony_ext'
create_makefile 'polyphony_ext'
