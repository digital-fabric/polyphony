# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/clean"

require "rake/extensiontask"
Rake::ExtensionTask.new("gyro_ext") do |ext|
  ext.ext_dir = "ext/gyro"
end

task :recompile => [:clean, :compile]

task :default => [:compile, :test]
task :test do
  exec 'ruby test/run.rb'
end

task :stress_test do
  exec 'ruby test/stress.rb'
end

task :docs do
  exec 'RUBYOPT=-W0 jekyll serve -s docs'
end

CLEAN.include "**/*.o", "**/*.so", "**/*.bundle", "**/*.jar", "pkg", "tmp"
