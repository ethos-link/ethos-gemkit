# frozen_string_literal: true

require "yaml"
require_relative "../gemkit"

module Ethos
  module Gemkit
    class Configuration
      KEYS = %w[gem_name repository version_file registry checks].freeze
      REGISTRIES = {"rubygems" => "https://rubygems.org", "github_packages" => "https://rubygems.pkg.github.com/ethos-link"}.freeze

      attr_reader :root, :data

      def self.load(root = Dir.pwd)
        path = File.join(root, ".ethos-gemkit.yml")
        new(root, File.exist?(path) ? YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false) : {})
      rescue Psych::Exception, Errno::ENOENT => error
        raise Error, "Cannot load .ethos-gemkit.yml: #{error.message}"
      end

      def initialize(root, data)
        @root = File.realpath(root)
        raise Error, "Configuration must be a mapping" unless data.is_a?(Hash)
        gemspecs = Dir[File.join(@root, "*.gemspec")]
        raise Error, "Expected exactly one gemspec, or an explicit gem_name" if !data["gem_name"] && !gemspecs.one?
        name = data["gem_name"] || File.basename(gemspecs.first, ".gemspec")
        versions = Dir[File.join(@root, "lib/**/version.rb")].reject { |file| file.include?("templates/") }
        registry = data.fetch("registry", "rubygems")
        registry = {"kind" => registry, "host" => REGISTRIES[registry]} if registry.is_a?(String)
        @data = {"gem_name" => name,
                 "repository" => "ethos-link/#{name}", "checks" => ["test"],
                 "version_file" => versions.one? ? versions.first.delete_prefix(@root + "/") : "lib/#{name}/version.rb"}.merge(data).merge("registry" => registry)
        validate
      end

      def name
        data.fetch("gem_name")
      end

      def checks
        data.fetch("checks")
      end

      def path(relative)
        unless relative.is_a?(String) && !relative.empty? && !Pathname.new(relative).absolute?
          raise Error, "Expected a relative repository path"
        end
        expanded = File.expand_path(relative, root)
        unless expanded.start_with?(root + File::SEPARATOR)
          raise Error, "Path escapes repository: #{relative}"
        end
        # Existing symlinks must stay inside the checkout too.
        parent = expanded
        parent = File.dirname(parent) until File.exist?(parent) || File.symlink?(parent)
        if File.symlink?(parent) && !File.exist?(parent)
          raise Error, "Dangling symlink is not a repository path: #{relative}"
        end
        unless File.realpath(parent).start_with?(root + File::SEPARATOR) || File.realpath(parent) == root
          raise Error, "Symlink escapes repository: #{relative}"
        end
        expanded
      end

      private

      def validate
        require_value(data.is_a?(Hash), "Configuration must be a mapping")
        require_value((data.keys - KEYS).empty?, "Unknown configuration keys: #{data.keys - KEYS}")
        require_value(name.is_a?(String) && name.match?(/\A[a-z0-9][a-z0-9_-]*\z/), "Invalid gem name")
        require_value(data["repository"].is_a?(String) && data["repository"].match?(/\A[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\z/), "Expected GitHub owner/repository")
        path(data.fetch("version_file"))
        registry = data["registry"]
        require_value(registry.is_a?(Hash) && registry.keys.sort == %w[host kind], "registry requires only kind and host")
        require_value(REGISTRIES.key?(registry["kind"]) && registry["host"] == REGISTRIES[registry["kind"]], "Unsupported registry/host pair")
        require_value(checks.is_a?(Array) && !checks.empty? && checks.all? { |check| check.is_a?(String) && check.match?(/\A[a-zA-Z][a-zA-Z0-9_:]*\z/) }, "checks must name existing Rake tasks")
        require_value(checks.none? { |check| %w[verify default release].include?(check) || check.start_with?("release:") }, "Verification checks must not recurse or publish")
      rescue KeyError => error
        raise Error, "Missing configuration: #{error.key}"
      end

      def require_value(condition, message)
        raise Error, message unless condition
      end
    end
  end
end
