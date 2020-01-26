require_relative './lib/polyphony/version'

Gem::Specification.new do |s|
  s.name        = 'polyphony'
  s.version     = Polyphony::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Polyphony: Fiber-based Concurrency for Ruby'
  s.author      = 'Sharon Rosner'
  s.email       = 'ciconia@gmail.com'
  s.files       = `git ls-files`.split
  s.homepage    = 'https://dfab.gitbook.io/polyphony/'
  s.metadata    = {
    "source_code_uri" => "https://github.com/digital-fabric/polyphony",
    "documentation_uri" => "https://digital-fabric.github.io/polyphony/",
    "homepage_uri" => "https://digital-fabric.github.io/polyphony/",
    "changelog_uri" => "https://github.com/digital-fabric/polyphony/blob/master/CHANGELOG.md"
  }
  s.rdoc_options = ["--title", "polyphony", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]
  s.extensions = ["ext/gyro/extconf.rb"]
  s.require_paths = ["lib"]
  s.required_ruby_version = '>= 2.6'

  s.add_runtime_dependency      'modulation',           '~>1.0'
  
  s.add_development_dependency  'httparty',             '0.17.0'
  s.add_development_dependency  'localhost',            '1.1.4'
  s.add_development_dependency  'minitest',             '5.13.0'
  s.add_development_dependency  'minitest-reporters',   '1.4.2'
  s.add_development_dependency  'simplecov',            '0.17.1'
  s.add_development_dependency  'rubocop',              '0.79.0'
  s.add_development_dependency  'pg',                   '1.1.3'
  s.add_development_dependency  'rake-compiler',        '1.0.5'
  s.add_development_dependency  'redis',                '4.1.0'
  s.add_development_dependency  'hiredis',              '0.6.3'
  s.add_development_dependency  'http_parser.rb',       '~>0.6.0'

  s.add_development_dependency  'jekyll',               '~>3.8.6'
  s.add_development_dependency  'jekyll-remote-theme',  '~>0.4.1'
  s.add_development_dependency  'jekyll-seo-tag',       '~>2.6.1'
  s.add_development_dependency  'just-the-docs',        '~>0.2.7'

end
