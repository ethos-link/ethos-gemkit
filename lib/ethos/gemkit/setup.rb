# frozen_string_literal: true

require "yaml"
require_relative "configuration"

module Ethos
  module Gemkit
    class Setup
      def initialize(root = Dir.pwd, checks: ["test"], release_mode: "staged")
        @root = File.realpath(root)
        @checks = checks
        @release_mode = release_mode
      end

      def changes
        gemspecs = Dir[File.join(@root, "*.gemspec")]
        raise Error, "Setup requires exactly one gemspec" unless gemspecs.one?
        spec = Gem::Specification.load(gemspecs.first)
        raise Error, "Cannot load gemspec" unless spec
        host = spec.metadata.fetch("allowed_push_host")
        kind = Configuration::REGISTRIES.key(host)
        raise Error, "Unsupported allowed_push_host" unless kind
        versions = Dir[File.join(@root, "lib/**/version.rb")].reject { |path| path.include?("templates/") }
        raise Error, "Configure version_file manually when multiple version files exist" unless versions.one?
        relative = versions.first.delete_prefix(@root + "/")
        config = {
          "schema_version" => 1, "workflow_contract" => CONTRACT,
          "gem_name" => spec.name, "repository" => "ethos-link/#{spec.name}",
          "default_branch" => "main", "version_file" => relative,
          "metadata_files" => [relative, "CHANGELOG.md", "Gemfile.lock"],
          "release_mode" => @release_mode,
          "registry" => {"kind" => kind, "host" => host}, "checks" => @checks
        }
        @configuration = Configuration.new(@root, config)
        result = {}
        path = @configuration.path(".ethos-gemkit.yml")
        if File.exist?(path)
          Configuration.load(@root)
        else
          result[".ethos-gemkit.yml"] = YAML.dump(config).delete_prefix("---\n")
        end
        standard = read(".standard.yml")
        updated = standard.sub(/^ruby_version:.*\n?/, "ruby_version: \"4.0\"\n")
        updated = "ruby_version: \"4.0\"\n" + updated unless updated.match?(/^ruby_version:/)
        plugins = YAML.safe_load(updated, aliases: false) || {}
        raise Error, ".standard.yml must be a mapping" unless plugins.is_a?(Hash)
        entries = plugins.fetch("plugins", [])
        unless entries.is_a?(Array)
          raise Error, ".standard.yml plugins must be an array"
        end
        if entries.any? { |entry| entry.is_a?(Hash) && (entry.key?("standard-rails") || entry.key?("ethos-gemkit")) }
          raise Error, "Remove manual Rails plugin options before setup; ethos-gemkit derives the framework target"
        end
        if entries.include?("standard-rails")
          updated = updated.sub(/^(\s*- )standard-rails$/, '\\1ethos-gemkit')
        elsif !plugins.fetch("plugins", []).include?("ethos-gemkit")
          if updated.match?(/^plugins:\s*$/)
            updated = updated.sub(/^plugins:\s*$/, "plugins:\n  - ethos-gemkit")
          else
            updated += "\nplugins:\n  - ethos-gemkit\n"
          end
        end
        result[".standard.yml"] = updated unless updated == standard
        rakefile = read("Rakefile")
        unless rakefile.include?('require "ethos/gemkit/tasks"')
          updated_rake = if rakefile.include?('require "standard/rake"')
            rakefile.sub('require "standard/rake"', 'require "ethos/gemkit/tasks"')
          else
            rakefile + "\nrequire \"ethos/gemkit/tasks\"\n"
          end
          result["Rakefile"] = updated_rake
        end
        result
      rescue Psych::Exception => error
        raise Error, "Invalid .standard.yml: #{error.message}"
      end

      def apply
        pending = changes
        pending.each { |name, content| File.write(@configuration.path(name), content) }
        pending.keys
      end

      private

      def read(name)
        path = @configuration.path(name)
        File.file?(path) ? File.read(path) : ""
      end
    end
  end
end
