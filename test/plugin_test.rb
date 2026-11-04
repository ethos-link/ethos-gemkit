# frozen_string_literal: true

require_relative "test_helper"

class PluginTest < GemkitTest
  TOOLKIT = File.expand_path("..", __dir__)

  def test_standard_cli_activates_rails_only_for_framework_bundles
    {"plain" => "", "support" => 'gem "activesupport", "~> 8.1"',
     "view" => 'gem "actionview", "~> 8.1"', "record" => 'gem "activerecord", "~> 8.1"',
     "rails" => 'gem "rails", "~> 8.1"'}.each do |profile, dependency|
      in_fixture do |directory|
        File.write(File.join(directory, "Gemfile"), <<~GEMFILE)
          source "https://rubygems.org"
          gem "ethos-gemkit", path: #{TOOLKIT.inspect}, require: false
          #{dependency}
        GEMFILE
        File.write(File.join(directory, ".standard.yml"), "ruby_version: \"4.0\"\nplugins:\n  - ethos-gemkit\n")
        File.write(File.join(directory, "probe.rb"), "Time.now\n")
        out, err, status = capture(directory, "bundle", "lock", "--local")
        assert status.success?, "#{profile}: #{out}#{err}"
        out, err, status = capture(directory, "bundle", "exec", "standardrb", "--format", "json", "probe.rb")
        assert [0, 1].include?(status.exitstatus), "#{profile}: #{out}#{err}"
        offenses = JSON.parse(out).fetch("files").flat_map { |file| file.fetch("offenses") }.map { |offense| offense.fetch("cop_name") }
        assert_equal %w[view record rails].include?(profile), offenses.include?("Rails/TimeZone"), "#{profile}: #{offenses} #{err}"
        File.write(File.join(directory, ".ethos-gemkit.yml"), YAML.dump(configuration))
        File.write(File.join(directory, "Rakefile"), 'require "ethos/gemkit/tasks"')
        rake_output, rake_error, rake_status = capture(directory, "bundle", "exec", "rake", "lint",
          environment: {"STANDARDOPTS" => "--format json probe.rb"})
        assert_equal status.exitstatus, rake_status.exitstatus, "#{profile}: #{rake_output}#{rake_error}"
        rake_offenses = JSON.parse(rake_output).fetch("files").flat_map { |file| file.fetch("offenses") }.map { |offense| offense.fetch("cop_name") }
        assert_equal offenses, rake_offenses, profile
        unless %w[view record rails].include?(profile)
          assert offenses.none? { |cop| cop.start_with?("Rails/") }, profile
        end
      end
    end
  end

  def test_incompatible_components_fail_before_linting
    require "ethos/gemkit/plugin"
    spec = Struct.new(:name, :version)
    resolver = Struct.new(:specs).new([spec.new("railties", Gem::Version.new("7.1.6"))])
    Bundler.stub(:load, resolver) do
      error = assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Plugin.new.rules(nil) }
      assert_match "consistent Rails 8", error.message
    end
  end
end
