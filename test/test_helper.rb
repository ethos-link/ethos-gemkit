# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require "bundler"
require "ethos/gemkit/configuration"
require "ethos/gemkit/tools"

class GemkitTest < Minitest::Test
  def tool_version(name)
    output, error, status = Open3.capture3("mise", "config", "get", "--file", File.join(Ethos::Gemkit::Tools::ROOT, "mise.toml"), "tools.#{name}")
    assert status.success?, error
    output.strip
  end

  def configuration(name = "fixture")
    {
      "gem_name" => name, "repository" => "ethos-link/#{name}",
      "version_file" => "lib/#{name}/version.rb", "checks" => ["test"],
      "registry" => {"kind" => "rubygems", "host" => "https://rubygems.org"}
    }
  end

  def in_fixture
    Dir.mktmpdir("gemkit-fixture-") { |directory| yield directory }
  end

  def capture(directory, *arguments, environment: {})
    Bundler.with_unbundled_env do
      roots = [*Gem.path, *Gem.loaded_specs.values.map(&:base_dir)].uniq
      paths = roots.join(File::PATH_SEPARATOR)
      executables = [*roots.map { |root| File.join(root, "bin") }, ENV.fetch("PATH")].join(File::PATH_SEPARATOR)
      Open3.capture3({"BUNDLE_GEMFILE" => File.join(directory, "Gemfile"), "GEM_PATH" => paths, "PATH" => executables}.merge(environment), *arguments, chdir: directory)
    end
  end
end
