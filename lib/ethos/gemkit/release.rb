# frozen_string_literal: true

require "open3"
require_relative "configuration"
require_relative "branch"

module Ethos
  module Gemkit
    class Release
      attr_reader :spec

      def initialize(config)
        @config = config
        @spec = Gem::Specification.load(config.path("#{config.name}.gemspec"))
        raise Error, "Cannot load gemspec" unless spec
      end

      # Ordinary uncommitted changes, reviewed and merged through the normal PR.
      # No commits, remote writes, tags, hook exceptions or persistent state.
      def prepare(target)
        Branch.check(@config.root)
        clean
        file = @config.path(@config.data.fetch("version_file"))
        text = File.read(file)
        current = spec.version.to_s
        parts = current.split(".").map(&:to_i)
        index = %w[major minor patch].index(target)
        if index
          parts[index] += 1
          ((index + 1)..2).each { |position| parts[position] = 0 }
          target = parts.join(".")
        end
        unless target.to_s.match?(/\A\d+\.\d+\.\d+\z/) && Gem::Version.new(target) > spec.version
          raise Error, "Use major, minor, patch or a newer X.Y.Z version"
        end
        literal = %(VERSION = "#{current}")
        raise Error, "Expected a literal #{literal} in version_file" unless text.include?(literal)
        raise Error, "Release tag already exists" unless git("tag", "--list", "v#{target}").empty? && git("ls-remote", "--tags", "origin", "refs/tags/v#{target}").empty?
        File.write(file, text.sub(literal, %(VERSION = "#{target}")))
        run("git-cliff", "--config", "cliff.toml", "--unreleased", "--tag", "v#{target}", "--prepend", "CHANGELOG.md")
        "Prepared v#{target}. Run bundle lock --local, review git diff, verify and commit through your PR."
      end

      def verify(tag)
        clean
        raise Error, "Tag and gem version differ" unless tag == "v#{spec.version}"
        origin = git("config", "--get", "remote.origin.url")
        repo = ENV.fetch("GITHUB_REPOSITORY", @config.data.fetch("repository"))
        unless ["https://github.com/#{repo}.git", "https://github.com/#{repo}", "git@github.com:#{repo}.git"].include?(origin)
          raise Error, "Release origin must be the canonical GitHub repository"
        end
        ref = "refs/tags/#{tag}"
        object = git("rev-parse", ref)
        raise Error, "Release tag must be annotated" unless git("cat-file", "-t", ref) == "tag"
        raise Error, "Tag must identify HEAD" unless git("rev-parse", "#{ref}^{}") == git("rev-parse", "HEAD")
        raise Error, "Canonical tag object differs" unless git("ls-remote", "--refs", "origin", ref).split.first == object
        git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
        git("merge-base", "--is-ancestor", "HEAD", "origin/main")
        spec.files.each do |file|
          unless git("hash-object", "--no-filters", "--", @config.path(file)) == git("rev-parse", "HEAD:#{file}")
            raise Error, "Package file differs from the release commit: #{file}"
          end
        end
        notes = File.read(@config.path("CHANGELOG.md")).split(/^## /).find { |section| section.lines.first.to_s.strip.match?(/\A\[#{Regexp.escape(spec.version.to_s)}\](?: - .*)?\z/) }
        raise Error, "Missing meaningful release notes" unless notes.to_s.lines.any? { |line| line.start_with?("- ") }
        "## #{notes}"
      end

      private

      def clean
        raise Error, "Release requires a clean working tree" unless git("status", "--porcelain").empty?
      end

      def git(*arguments)
        run("git", *arguments).strip
      end

      def run(*arguments)
        output, error, status = Open3.capture3(*arguments, chdir: @config.root)
        raise Error, "#{arguments.first(3).join(" ")} failed: #{output}#{error}" unless status.success?
        output
      end
    end
  end
end
