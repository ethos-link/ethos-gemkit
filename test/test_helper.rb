# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "open3"
require "json"
require "bundler"
require "ethos/gemkit/configuration"

class GemkitTest < Minitest::Test
  def configuration(name = "fixture")
    {
      "schema_version" => 1, "workflow_contract" => 1, "gem_name" => name,
      "repository" => "ethos-link/#{name}", "default_branch" => "main",
      "version_file" => "lib/#{name}/version.rb", "metadata_files" => ["CHANGELOG.md"],
      "release_mode" => "staged", "checks" => ["test"],
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
