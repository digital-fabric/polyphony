# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/clean"

# frozen_string_literal: true

require "rake/extensiontask"
Rake::ExtensionTask.new("gyro_ext") do |ext|
  ext.ext_dir = "ext/gyro"
end

task :default => [:compile, :test]
task :test do
  exec 'ruby test/run.rb'
end

task default: %w[compile]

CLEAN.include "**/*.o", "**/*.so", "**/*.bundle", "**/*.jar", "pkg", "tmp"
