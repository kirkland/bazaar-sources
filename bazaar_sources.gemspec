# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

Gem::Specification.new do |s|
  s.name = "bazaar_sources"
  s.rubyforge_project = "bazaar-sources"
  s.version = '0.2.1.1.1.3'

  s.authors = ["chris mcc"]
  s.email = ["cmcclelland@digitaladvisor.com"]
  s.description = "Bazaar Sources"

  s.files = Dir.glob("lib/**/*") + %w(README.rdoc init.rb)

  s.homepage = "http://github.com/DigitalAdvisor/bazaar-sources"
  s.rdoc_options = ["--main", "README"]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.3.6"
  s.summary = "Bazaar sources is real cool"

  s.add_runtime_dependency("crack", [">= 0.1.7"])
  s.add_runtime_dependency("hpricot")
  s.add_runtime_dependency("httparty")
  s.add_runtime_dependency("nokogiri")
end