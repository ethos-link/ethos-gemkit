# frozen_string_literal: true

require "rake"
require "standard/rake"
require_relative "configuration"
require_relative "package"
require_relative "doctor"

# Loading is explicit: downstream runtime requires never install these tasks.
config = Ethos::Gemkit::Configuration.load

desc "Run Standard with bundle-aware Rails rules"
task lint: :standard

desc "Apply Standard's safe corrections"
task "lint:fix" => "standard:fix"

desc "Validate and build a disposable gem package"
task "package:verify" do
  Ethos::Gemkit::Package.new(config).verify
end

desc "Run lint, repository checks and package validation"
task verify: [:lint, *config.checks, "package:verify"]

desc "Diagnose shared tooling configuration and hook installation"
task "ethos:doctor" do
  Ethos::Gemkit::Doctor.new(config).check
  puts "ethos-gemkit #{Ethos::Gemkit::VERSION}: #{config.name} configured"
end
