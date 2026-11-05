# frozen_string_literal: true

require "open3"
require_relative "../gemkit"

module Ethos
  module Gemkit
    module Tools
      ROOT = File.expand_path("../../..", __dir__)

      # Resolve against the installed gem, even when called from a consumer.
      # --tool prevents an unrelated executable on PATH from satisfying lookup.
      def self.executable(name)
        output, error, status = Open3.capture3("mise", "--cd", ROOT, "which", "--tool", name, name)
        unless status.success? && File.executable?(output.strip)
          raise Error, "Install pinned #{name} with bundle exec rake tools:install: #{error.strip}"
        end
        output.strip
      rescue Errno::ENOENT
        raise Error, "Install mise, then run bundle exec rake tools:install"
      end
    end
  end
end
