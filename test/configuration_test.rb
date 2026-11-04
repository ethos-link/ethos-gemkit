# frozen_string_literal: true

require_relative "test_helper"

class ConfigurationTest < GemkitTest
  def test_rejects_invalid_registry_and_configuration_before_mutation
    in_fixture do |directory|
      [configuration.merge("schema_version" => 2),
        configuration.merge("unexpected" => true),
        configuration.merge("checks" => ["release:prepare"]),
        configuration.merge("checks" => ["release:publish"]),
        configuration.merge("registry" => {"kind" => "github_packages", "host" => "https://rubygems.org"}),
        configuration.merge("registry" => {"kind" => "unknown", "host" => "https://rubygems.org"}),
        configuration.merge("version_file" => "../secret.rb"),
        configuration.merge("version_file" => "/etc/passwd")].each do |data|
        assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Configuration.new(directory, data) }
      end
    end
  end

  def test_yaml_objects_and_aliases_are_not_executable_configuration
    in_fixture do |directory|
      File.write(File.join(directory, ".ethos-gemkit.yml"), "--- !ruby/object:Object {}\n")
      assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Configuration.load(directory) }
      File.write(File.join(directory, ".ethos-gemkit.yml"), "defaults: &defaults {}\ncopy: *defaults\n")
      assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Configuration.load(directory) }
    end
  end

  def test_symlink_must_not_escape_the_repository
    in_fixture do |directory|
      Dir.mktmpdir do |external|
        File.symlink(external, File.join(directory, "lib"))
        assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Configuration.new(directory, configuration) }
      end
    end
  end
end
