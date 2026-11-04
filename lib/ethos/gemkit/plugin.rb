# frozen_string_literal: true

require "bundler"
require "lint_roller"
require_relative "../gemkit"

module Ethos
  module Gemkit
    # Delegate through lint_roller's public interface; never mutate RuboCop internals.
    class Plugin < LintRoller::Plugin
      FRAMEWORKS = %w[rails railties activerecord activemodel actionpack actionview activejob actionmailer activestorage actioncable actionmailbox actiontext].freeze

      def about
        LintRoller::About.new(name: "ethos-gemkit", version: VERSION,
          homepage: "https://github.com/ethos-link/ethos-gemkit",
          description: "Standard Rails rules when framework components are bundled")
      end

      def supported?(context)
        true
      end

      def rules(context)
        specs = Bundler.load.specs.select { |spec| FRAMEWORKS.include?(spec.name) }
        if specs.empty?
          LintRoller::Rules.new(type: :object, config_format: :rubocop, value: {})
        else
          versions = specs.map { |spec| spec.version.segments.first(2) }.uniq
          if versions.size != 1 || versions.first.first != 8
            raise Error, "Rails linting requires consistent Rails 8 components; found #{specs.map { |spec| "#{spec.name}=#{spec.version}" }.join(", ")}"
          end
          require "standard/rails"
          Standard::Rails::Plugin.new(@config.merge("target_rails_version" => versions.first.join(".").to_f)).rules(context)
        end
      rescue LoadError => error
        raise Error, "Install compatible standard-rails support with bundle install: #{error.message}"
      end
    end
  end
end
