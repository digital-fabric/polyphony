# frozen_string_literal: true

require 'coverage'
require 'simplecov'

# Since we load code using Modulation, and the stock coverage gem does not
# calculate coverage for code loaded using `Kernel#eval` et al, we need to use
# the TracePoint API in order to trace execution. Here we monkey-patch the two
# main Coverage class methods, start and result to use TracePoint. Otherwise we
# let SimpleCov do its business.
module Coverage
  EXCLUDE = %w{coverage eg helper run
  }.map { |n| File.expand_path("test/#{n}.rb") }

  LIB_FILES = Dir["#{File.join(FileUtils.pwd, 'lib')}/polyphony/**/*.rb"]

  class << self
    def relevant_lines_for_filename(filename)
      @classifier ||= SimpleCov::LinesClassifier.new
      @classifier.classify(IO.read(filename).lines)
    end

    def start
      @result = {}
      trace = TracePoint.new(:line) do |tp|
        next if tp.path =~ /\(/
      
        absolute = File.expand_path(tp.path)
        next unless LIB_FILES.include?(absolute)# =~ /^#{LIB_DIR}/
        
        @result[absolute] ||= relevant_lines_for_filename(absolute)
        @result[absolute][tp.lineno - 1] = 1
      end
      trace.enable
    end

    def result
      @result
    end
  end
end

class << SimpleCov::LinesClassifier
  alias_method :orig_whitespace_line?, :whitespace_line?
  def whitespace_line?(line)
    # apparently TracePoint tracing does not cover lines including only keywords
    # such as begin end etc, so here we mark those lines as whitespace, so they
    # won't count towards the coverage score.
    line.strip =~ /^(begin|end|ensure|else|\})|(\s*rescue\s.+)$/ ||
                  orig_whitespace_line?(line)
  end
end

SimpleCov.start