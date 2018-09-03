Gem::Specification.new do |s|
  s.name        = 'nuclear'
  s.version     = '0.2'
  s.licenses    = ['MIT']
  s.summary     = 'Nuclear: lightweight reactor for Ruby'
  s.author      = 'Sharon Rosner'
  s.email       = 'ciconia@gmail.com'
  s.files       = `git ls-files README.md CHANGELOG.md lib`.split
  s.homepage    = 'http://github.com/ciconia/nuclear'
  s.metadata    = {
    "source_code_uri" => "https://github.com/ciconia/nuclear"
  }
  s.rdoc_options = ["--title", "Nuclear", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]

  s.add_runtime_dependency 'modulation', '0.12'
  s.add_runtime_dependency 'nio4r', '2.3.1'
end