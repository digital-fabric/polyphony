require_relative './lib/rubato/version'

Gem::Specification.new do |s|
  s.name        = 'rubato'
  s.version     = Rubato::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Rubato: Fiber-based Concurrency for Ruby'
  s.author      = 'Sharon Rosner'
  s.email       = 'ciconia@gmail.com'
  s.files       = `git ls-files README.md CHANGELOG.md lib`.split
  s.homepage    = 'http://github.com/ciconia/rubato'
  s.metadata    = {
    "source_code_uri" => "https://github.com/ciconia/rubato"
  }
  s.rdoc_options = ["--title", "rubato", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]
  s.extensions = ["ext/ev/extconf.rb"]
  s.require_paths = ["lib"]

  s.add_runtime_dependency      'modulation',     '0.15'
  
  s.add_runtime_dependency      'http_parser.rb', '0.6.0'
  s.add_runtime_dependency      'http-2',         '0.10.0'
  
  # s.add_runtime_dependency      'hiredis',        '0.6.1'
  # s.add_runtime_dependency      'pg',             '1.0.0'

  s.add_development_dependency  'rake-compiler',  '1.0.5'
  s.add_development_dependency  'minitest',       '5.11.3'
  s.add_development_dependency  'localhost',      '1.1.4'
end
