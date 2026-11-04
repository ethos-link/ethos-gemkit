# frozen_string_literal: true

require_relative "test_helper"
require "ethos/gemkit/package"

class PackageTest < GemkitTest
  def fixture(directory, ruby: ">= 4.0", host: "https://rubygems.org", extra: "")
    File.write(File.join(directory, "fixture.rb"), "module Fixture; end\n")
    File.write(File.join(directory, "fixture.gemspec"), <<~SPEC)
      Gem::Specification.new do |s|
        s.name = "fixture"
        s.version = "1.0.0"
        s.authors = ["Test"]
        s.summary = "Package fixture"
        s.license = "MIT"
        s.homepage = "https://example.com"
        s.required_ruby_version = #{ruby.inspect}
        s.metadata["allowed_push_host"] = #{host.inspect}
        s.files = ["fixture.rb"]
        #{extra}
      end
    SPEC
    Ethos::Gemkit::Configuration.new(directory, configuration)
  end

  def test_builds_without_git_and_leaves_no_package_artifact
    in_fixture do |directory|
      assert Ethos::Gemkit::Package.new(fixture(directory)).verify
      assert_empty Dir[File.join(directory, "*.gem")]
    end
  end

  def test_rejects_unsafe_metadata_or_runtime_toolkit_dependency
    in_fixture do |directory|
      [{ruby: ">= 3.2"}, {host: "https://other.example"}, {extra: 's.add_dependency "ethos-gemkit"'}].each do |options|
        config = fixture(directory, **options)
        assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Package.new(config).verify }
      end
    end
  end
end
