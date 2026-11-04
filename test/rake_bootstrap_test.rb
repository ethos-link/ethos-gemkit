# frozen_string_literal: true

require_relative "test_helper"

class RakeBootstrapTest < GemkitTest
  TOOLKIT = File.expand_path("..", __dir__)

  def test_plain_rake_loads_the_toolkit_checkout_without_bundle_exec
    output, error, status = capture(TOOLKIT, RbConfig.ruby, "-S", "rake", "-T")
    assert status.success?, output + error
    assert_includes output, "release:build"
    assert_includes output, "verify"
  end

  def test_documented_bootstrap_loads_an_uninstalled_consumer_dependency
    in_fixture do |directory|
      File.write(File.join(directory, "Gemfile"), <<~GEMFILE)
        source "https://rubygems.org"
        gemspec
        gem "ethos-gemkit", path: #{TOOLKIT.inspect}, require: false
      GEMFILE
      File.write(File.join(directory, "fixture.gemspec"), <<~SPEC)
        Gem::Specification.new do |spec|
          spec.name = "fixture"
          spec.version = "1.0.0"
          spec.summary = "Bootstrap fixture"
          spec.authors = ["Test"]
        end
      SPEC
      File.write(File.join(directory, "Rakefile"), File.read(File.join(TOOLKIT, "Rakefile")))
      File.write(File.join(directory, ".standard.yml"), "ruby_version: \"4.0\"\nplugins:\n  - ethos-gemkit\n")
      output, error, status = capture(directory, "bundle", "lock", "--local")
      assert status.success?, output + error
      output, error, status = capture(directory, RbConfig.ruby, "-S", "rake", "-T")
      assert status.success?, output + error
      assert_includes output, "release:prepare"
      assert_includes output, "verify"
    end
  end
end
