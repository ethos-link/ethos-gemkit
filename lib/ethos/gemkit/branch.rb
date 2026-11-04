# frozen_string_literal: true

require "open3"
require_relative "../gemkit"

module Ethos
  module Gemkit
    class Branch
      def self.check(root = Dir.pwd)
        output, error, status = Open3.capture3("git", "branch", "--show-current", chdir: root)
        raise Error, "Cannot inspect Git branch: #{error.strip}" unless status.success?
        branch = output.strip
        if branch.empty? || %w[main master].include?(branch)
          raise Error, "Use a feature branch; direct commits to main/master or detached HEAD are blocked"
        end
        true
      end
    end
  end
end
