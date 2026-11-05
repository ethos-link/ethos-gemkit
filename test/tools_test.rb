# frozen_string_literal: true

require_relative "test_helper"

class ToolsTest < GemkitTest
  def test_pinned_binaries_resolve_from_a_consumer_directory
    in_fixture do |directory|
      %w[git-cliff gh].each do |name|
        executable = Dir.chdir(directory) { Ethos::Gemkit::Tools.executable(name) }
        output, error, status = Open3.capture3(executable, "--version", chdir: directory)
        assert status.success?, error
        assert_match(/\A#{Regexp.escape(name)}(?: version)? #{Regexp.escape(tool_version(name))}(?:\s|\z)/, output)
      end
    end
  end

  def test_failed_lookup_does_not_fall_back_to_path
    failure = Struct.new(:success?).new(false)
    Open3.stub(:capture3, ["/usr/bin/gh\n", "not installed", failure]) do
      error = assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Tools.executable("gh") }
      assert_includes error.message, "bundle exec rake tools:install"
    end
  end

  def test_missing_mise_explains_setup
    Open3.stub(:capture3, ->(*) { raise Errno::ENOENT }) do
      error = assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Tools.executable("git-cliff") }
      assert_includes error.message, "Install mise"
    end
  end

  def test_gem_ships_the_shared_manifest_and_lockfile
    spec = Gem::Specification.load(File.join(Ethos::Gemkit::Tools::ROOT, "ethos-gemkit.gemspec"))
    assert_includes spec.files, "mise.toml"
    assert_includes spec.files, "mise.lock"
    refute spec.files.any? { |file| file.include?("node_modules") || file.include?("package-lock.json") }
  end
end
