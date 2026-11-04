# frozen_string_literal: true

require "open3"
require_relative "configuration"

module Ethos
  module Gemkit
    class Doctor
      def initialize(config)
        @config = config
      end

      def check
        problems = []
        configuration = YAML.safe_load_file(@config.path(".standard.yml"), aliases: false)
        raise Error, ".standard.yml must be a mapping" unless configuration.is_a?(Hash)
        plugins = configuration.fetch("plugins", [])
        raise Error, ".standard.yml plugins must be an array" unless plugins.is_a?(Array)
        problems << ".standard.yml must register ethos-gemkit" unless plugins.include?("ethos-gemkit")
        problems << "Standard must target Ruby 4.0" unless configuration["ruby_version"].to_s == "4.0"
        %w[pre-commit commit-msg].each do |hook|
          output, status = Open3.capture2("git", "rev-parse", "--git-path", "hooks/#{hook}", chdir: @config.root)
          unless status.success? && File.executable?(File.expand_path(output.strip, @config.root))
            problems << "Install #{hook} with bundle exec lefthook install"
          end
        end
        raise Error, problems.join("\n") unless problems.empty?
        true
      rescue Psych::Exception, Errno::ENOENT, KeyError => error
        raise Error, "Incomplete tooling setup: #{error.message}"
      end
    end
  end
end
