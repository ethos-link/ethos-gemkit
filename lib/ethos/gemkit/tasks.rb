# frozen_string_literal: true

require "standard/rake"
require_relative "configuration"
require_relative "package"
require_relative "tools"

config = Ethos::Gemkit::Configuration.load
standard = YAML.safe_load_file(config.path(".standard.yml"), aliases: false)
unless standard.is_a?(Hash) && standard["ruby_version"].to_s == "4.0" && Array(standard["plugins"]).include?("ethos-gemkit")
  raise Ethos::Gemkit::Error, ".standard.yml must target Ruby 4.0 and register ethos-gemkit"
end
task lint: :standard
task "lint:fix" => "standard:fix"
desc "Install pinned development binaries with mise"
task "tools:install" do
  sh "mise", "trust", File.join(Ethos::Gemkit::Tools::ROOT, "mise.toml")
  sh "mise", "--cd", Ethos::Gemkit::Tools::ROOT, "install", "--locked", "git-cliff", "gh"
end
task "package:verify" do
  Ethos::Gemkit::Package.new(config).verify
end

desc "Run lint, gem checks, package validation and changelog validation"
task verify: [:lint, *config.checks, "package:verify"] do
  require "tempfile"
  Tempfile.create("gemkit-changelog") { |file| sh Ethos::Gemkit::Tools.executable("git-cliff"), "--config", "cliff.toml", "--unreleased", "--output", file.path }
end
