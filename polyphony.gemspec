require_relative './lib/polyphony/version'

Gem::Specification.new do |s|
  s.name        = 'polyphony'
  s.version     = Polyphony::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Polyphony: Fiber-based Concurrency for Ruby'
  s.author      = 'Sharon Rosner'
  s.email       = 'ciconia@gmail.com'
  s.files       = `git ls-files`.split
  s.homepage    = 'http://github.com/digital-fabric/polyphony'
  s.metadata    = {
    "source_code_uri" => "https://github.com/digital-fabric/polyphony"
  }
  s.rdoc_options = ["--title", "polyphony", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]
  s.extensions = ["ext/ev/extconf.rb"]
  s.require_paths = ["lib"]

  s.add_runtime_dependency      'modulation',     '0.23'
  
  s.add_runtime_dependency      'http_parser.rb', '0.6.0'
  s.add_runtime_dependency      'http-2',         '0.10.0'
  
  # s.add_runtime_dependency      'hiredis',        '0.6.1'
  # s.add_runtime_dependency      'pg',             '1.0.0'

  s.add_development_dependency  'rake-compiler',  '1.0.5'
  s.add_development_dependency  'minitest',       '5.11.3'
  s.add_development_dependency  'localhost',      '1.1.4'
  s.add_development_dependency  'websocket',      '1.2.8'
  s.add_development_dependency  'pg',             '1.1.3'
  s.add_development_dependency  'redis',          '4.1.0'
  s.add_development_dependency  'hiredis',        '0.6.3'
end
