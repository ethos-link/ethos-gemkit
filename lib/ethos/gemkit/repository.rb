# frozen_string_literal: true

require "open3"
require "bundler"
require_relative "configuration"

module Ethos
  module Gemkit
    class Repository
      attr_reader :config

      def initialize(config, origin: nil)
        @config = config
        repository = config.data.fetch("repository")
        @origins = origin ? [origin] : ["https://github.com/#{repository}.git", "https://github.com/#{repository}",
          "git@github.com:#{repository}.git", "ssh://git@github.com/#{repository}.git"]
      end

      def run(*arguments, environment: {})
        env = Bundler.unbundled_env.merge("BUNDLE_GEMFILE" => File.join(config.root, "Gemfile"))
        env["GEM_PATH"] = [*Gem.path, *Gem.loaded_specs.values.map(&:base_dir)].uniq.join(File::PATH_SEPARATOR)
        output, error, status = Open3.capture3(env.merge(environment), *arguments, chdir: config.root, unsetenv_others: true)
        unless status.success?
          raise Error, "#{arguments.first(2).join(" ")} failed: #{output}#{error}"
        end
        output
      end

      def git(*arguments)
        run("git", *arguments).strip
      end

      def success?(*arguments)
        _, _, status = Open3.capture3(*arguments, chdir: config.root)
        status.success?
      end

      def validate_origin
        [git("remote", "get-url", "--all", "origin"), git("remote", "get-url", "--push", "--all", "origin")].each do |value|
          raise Error, "Origin must resolve to one canonical repository URL" unless @origins.include?(value)
        end
      end

      def clean
        raise Error, "Release requires a clean working tree including untracked files" unless git("status", "--porcelain").empty?
      end

      def main(current: true)
        raise Error, "Prepare releases from main" unless git("branch", "--show-current") == "main"
        validate_origin
        %w[pre-commit commit-msg].each do |hook|
          path = File.expand_path(git("rev-parse", "--git-path", "hooks/#{hook}"), config.root)
          raise Error, "Install repository hooks before preparing a release" unless File.executable?(path)
        end
        fetch_main
        if current && git("rev-parse", "HEAD") != git("rev-parse", "origin/main")
          raise Error, "main must be current with origin/main"
        end
      end

      def fetch_main
        validate_origin
        git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
      end

      def remote_tag(tag)
        git("ls-remote", "--refs", "--tags", "origin", "refs/tags/#{tag}").split.first
      end

      def journal
        File.expand_path(git("rev-parse", "--git-path", "ethos-gemkit-release.json"), config.root)
      end
    end
  end
end
