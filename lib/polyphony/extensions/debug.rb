module ::Kernel
  def trace(*args)
    STDOUT.orig_write(format_trace(args))
  end

  def format_trace(args)
    if args.size > 1 && args.first.is_a?(String)
      format("%s: %p\n", args.shift, args.size == 1 ? args.first : args)
    else
      format("%p\n", args.size == 1 ? args.first : args)
    end
  end
end