# frozen_string_literal: true

require "uri"
require_relative "repository"

module Ethos
  module Gemkit
    class GitlabSync
      def self.validate_url(url)
        match = /\Agit@([a-zA-Z0-9.-]+):([a-zA-Z0-9_.-]+(?:\/[a-zA-Z0-9_.-]+)+)\.git\z/.match(url)
        unless match && match[1].include?(".") && match[2].split("/").none? { |part| %w[. ..].include?(part) }
          raise Error, "gitlab_url must be an SSH Git URL such as git@gitlab.com:group/project.git"
        end
        match[1]
      end

      def initialize(config, repository: Repository.new(config))
        @config, @repository = config, repository
      end

      def run
        target = @config.gitlab_url
        return "GitLab sync skipped: no gitlab_url configured" unless target
        self.class.validate_url(target)
        @repository.fetch_main
        expected = @repository.git("rev-parse", "refs/remotes/origin/main")
        # No consumer hooks, tags, pruning or forced updates in a credentialed job.
        @repository.git("-c", "core.hooksPath=/dev/null", "push", "--no-follow-tags", target,
          "refs/remotes/origin/main:refs/heads/main")
        actual = @repository.git("ls-remote", "--refs", target, "refs/heads/main").split.first
        raise Error, "GitLab main differs after synchronization" unless actual == expected
        "GitLab main synchronized to #{expected}"
      end
    end
  end
end
