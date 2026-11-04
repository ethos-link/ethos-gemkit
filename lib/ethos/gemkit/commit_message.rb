# frozen_string_literal: true

require "commitlint"
require_relative "../gemkit"

module Ethos
  module Gemkit
    class CommitMessage
      TYPES = %w[feat fix chore refactor docs test perf ci build].freeze

      def self.validate(message)
        cleaned = message.lines.reject { |line| line.start_with?("#") }.join.strip
        header = cleaned.lines.first.to_s.chomp
        type = header[/\A([a-z]+)(?:\([^)\n]+\))?!?: \S/, 1]
        unless TYPES.include?(type)
          raise Error, "Use a Conventional Commit header with one of: #{TYPES.join(", ")}"
        end
        raise Error, "Commit subject must be at most 72 characters" if header.length > 72
        if cleaned.lines.size > 1 && !cleaned.lines[1].strip.empty?
          raise Error, "Separate the commit subject and body with a blank line"
        end

        # Upstream has a fixed type list without ci/build. Adapt only its grammar
        # input after validating our policy; never change the actual commit text.
        grammar = cleaned.sub(/\A(?:build|ci)(?=[:(!])/, "chore")
        validator = ::Commitlint::Validator.new(grammar)
        raise Error, validator.errors.join("\n") unless validator.valid?
        true
      end
    end
  end
end
