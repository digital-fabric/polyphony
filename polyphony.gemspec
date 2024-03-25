require_relative './lib/polyphony/version'

Gem::Specification.new do |s|
  s.name        = 'polyphony'
  s.version     = Polyphony::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Fine grained concurrency for Ruby'
  s.author      = 'Sharon Rosner'
  s.email       = 'sharon@noteflakes.com'
  s.files       = `git ls-files --recurse-submodules`.split.reject { |fn| fn =~ /liburing\/man/ }
  s.homepage    = 'https://github.com/digital-fabric/polyphony'
  s.metadata    = {
    "source_code_uri" => "https://github.com/digital-fabric/polyphony",
    "documentation_uri" => "https://www.rubydoc.info/gems/polyphony",
    "changelog_uri" => "https://github.com/digital-fabric/polyphony/blob/master/CHANGELOG.md"
  }
  s.rdoc_options = ["--title", "polyphony", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]
  s.extensions = ["ext/polyphony/extconf.rb"]
  s.require_paths = ["lib"]
  s.required_ruby_version = '>= 3.1'

  s.add_development_dependency  'rake-compiler',        '1.2.7'
  s.add_development_dependency  'minitest',             '5.22.3'
  s.add_development_dependency  'simplecov',            '0.22.0'
  s.add_development_dependency  'rubocop',              '1.62.1'
  s.add_development_dependency  'pry',                  '0.14.2'

  s.add_development_dependency  'msgpack',              '1.7.2'
  s.add_development_dependency  'httparty',             '0.21.0'
  s.add_development_dependency  'localhost',            '1.2.0'
  s.add_development_dependency  'debug',                '1.9.1'
  s.add_development_dependency  'benchmark-ips',        '2.13.0'

  # FIXME: remove gems when all other dependencies have bundled them (not part of stdlib since Ruby 3.4)
  s.add_development_dependency  'base64',               '0.2.0'
  s.add_development_dependency  'bigdecimal',           '3.1.7'
  s.add_development_dependency  'csv',                  '3.3.0'
  s.add_development_dependency  'mutex_m',              '0.2.0'
end
