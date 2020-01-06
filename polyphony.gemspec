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
  s.extensions = ["ext/gyro/extconf.rb"]
  s.require_paths = ["lib"]
  s.required_ruby_version = '>= 2.6'

  s.executables   = ['poly']

  s.add_runtime_dependency      'modulation',     '~>0.25'
  
  s.add_runtime_dependency      'http_parser.rb', '0.6.0'
  s.add_runtime_dependency      'http-2',         '0.10.0'
  s.add_runtime_dependency      'rack'
  
  s.add_development_dependency  'hiredis',            '0.6.3'
  s.add_development_dependency  'httparty',           '0.17.0'
  s.add_development_dependency  'localhost',          '1.1.4'
  s.add_development_dependency  'minitest',           '5.11.3'
  s.add_development_dependency  'minitest-reporters', '1.4.2'
  s.add_development_dependency  'simplecov',          '0.17.1'
  s.add_development_dependency  'pg',                 '1.1.3'
  s.add_development_dependency  'rake-compiler',      '1.0.5'
  s.add_development_dependency  'redis',              '4.1.0'
  s.add_development_dependency  'websocket',          '1.2.8'
end
