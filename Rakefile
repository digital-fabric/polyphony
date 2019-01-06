# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/clean"

# frozen_string_literal: true

require "rake/extensiontask"
Rake::ExtensionTask.new("ev_ext") do |ext|
  ext.ext_dir = "ext/ev"
end

task :default => [:compile, :test]
task :test do
  Dir.glob('./test/test_*.rb').each { |file| require(file) }
end

# task default: %w[compile]# spec rubocop]

CLEAN.include "**/*.o", "**/*.so", "**/*.bundle", "**/*.jar", "pkg", "tmp"
