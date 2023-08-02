# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/clean"

require "rake/extensiontask"
Rake::ExtensionTask.new("polyphony_ext") do |ext|
  ext.ext_dir = "ext/polyphony"
end

task :recompile => [:clean, :compile]
task :default => [:compile, :test]

task :test do
  exec 'ruby test/run.rb'
end

task :stress_test do
  exec 'ruby test/stress.rb'
end

CLEAN.include "**/*.o", "**/*.so", "**/*.so.*", "**/*.a", "**/*.bundle", "**/*.jar", "pkg", "tmp"

task :release do
  require_relative './lib/polyphony/version'
  version = Polyphony::VERSION

  puts 'Building polyphony...'
  `gem build polyphony.gemspec`

  puts "Pushing polyphony #{version}..."
  `gem push polyphony-#{version}.gem`

  puts "Cleaning up..."
  `rm *.gem`
end
