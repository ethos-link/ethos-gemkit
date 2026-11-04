# frozen_string_literal: true

require "rubygems/package"
require "tmpdir"
require_relative "configuration"

module Ethos
  module Gemkit
    class Package
      def initialize(config)
        @config = config
      end

      def verify
        Dir.chdir(@config.root) do
          spec = Gem::Specification.load(@config.path("#{@config.name}.gemspec"))
          raise Error, "Cannot load gemspec" unless spec
          validate_spec(spec)
          Dir.mktmpdir("ethos-gemkit-package-") do |directory|
            artifact = File.join(directory, "#{spec.full_name}.gem")
            Gem::Package.build(spec, false, false, artifact)
            package = Gem::Package.new(artifact)
            package.verify
            unless package.spec.dependencies.none? { |dependency| dependency.type == :runtime && dependency.name == "ethos-gemkit" }
              raise Error, "ethos-gemkit must not be a runtime dependency"
            end
          end
        end
        true
      end

      private

      def validate_spec(spec)
        raise Error, "Configured gem name differs from gemspec" unless spec.name == @config.name
        requirement = spec.required_ruby_version
        unless requirement.satisfied_by?(Gem::Version.new("4.0.0")) && !requirement.satisfied_by?(Gem::Version.new("3.4.99"))
          raise Error, "Gems must require Ruby 4.0 or newer"
        end
        unless spec.metadata["allowed_push_host"] == @config.data.fetch("registry").fetch("host")
          raise Error, "allowed_push_host differs from configured registry"
        end
        raise Error, "Package contains no files" if spec.files.empty?
        spec.files.each do |file|
          @config.path(file)
          if file.match?(%r{(?:\A|/)(?:\.git|\.bundle|node_modules|coverage)(?:/|\z)|(?:\A|/)(?:master\.key|credentials\.yml|\.env(?:\..*)?)\z})
            raise Error, "Unsafe package path: #{file}"
          end
        end
      end
    end
  end
end
