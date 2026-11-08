# frozen_string_literal: true

require_relative "lib/ethos/gemkit/version"

Gem::Specification.new do |spec|
  spec.name = "ethos-gemkit"
  spec.version = Ethos::Gemkit::VERSION
  spec.authors = ["Ethos Link"]
  spec.email = ["devel@ethos-link.com"]
  spec.summary = "Shared development and verification tooling for Ethos Link gems"
  spec.description = "Common Ruby gem tasks, conditional Rails linting, package validation and release verification."
  spec.homepage = "https://www.ethos-link.com/opensource/ethos-gemkit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => spec.homepage,
    "bug_tracker_uri" => "https://github.com/ethos-link/ethos-gemkit/issues",
    "allowed_push_host" => "https://rubygems.org",
    "source_code_uri" => "https://github.com/ethos-link/ethos-gemkit",
    "changelog_uri" => "https://github.com/ethos-link/ethos-gemkit/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true",
    "default_lint_roller_plugin" => "Ethos::Gemkit::Plugin"
  }
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "docs/**/*.md", "exe/*", "mise.toml", "mise.lock", "README.md", "UPGRADE.md", "LICENSE.txt", "CHANGELOG.md"].select { |file| File.file?(file) } }
  spec.bindir = "exe"
  spec.executables = ["ethos-gemkit"]
  spec.require_paths = ["lib"]
  spec.add_dependency "standard", "~> 1.57"
  spec.add_dependency "standard-rails", "~> 1.6"
  spec.add_dependency "lint_roller", "~> 1.1"
  spec.add_dependency "rake", "~> 13.0"
  spec.add_dependency "lefthook", "~> 2.1"
end
