# frozen_string_literal: true

require "open3"
require "bundler"
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

      # Release metadata uses an ordinary branch and PR; main is never committed.
      def prepare(target = "patch")
        progress "Checking working tree and repository"
        clean
        canonical_origin
        progress "Fetching origin/main"
        git("fetch", "--no-tags", "origin", "refs/heads/main:refs/remotes/origin/main")
        unless git("rev-parse", "HEAD") == git("rev-parse", "origin/main")
          raise Error, "Start from clean main at origin/main; fetch and fast-forward before preparing a release"
        end
        %w[pre-commit commit-msg].each do |hook|
          path = File.expand_path(git("rev-parse", "--git-path", "hooks/#{hook}"), @config.root)
          raise Error, "Install hooks with bundle exec lefthook install" unless File.executable?(path)
        end
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
        unless target.to_s.match?(/\A\d+\.\d+\.\d+\z/) && Gem::Version.new(target) >= spec.version
          raise Error, "Use major, minor, patch or a X.Y.Z version that has not been tagged"
        end
        literal = %(VERSION = "#{current}")
        raise Error, "Expected a literal #{literal} in version_file" unless text.include?(literal)
        progress "Checking release tag v#{target}"
        raise Error, "Release tag already exists" unless git("tag", "--list", "v#{target}").empty? && git("ls-remote", "--tags", "origin", "refs/tags/v#{target}").empty?
        branch = "chore/release-v#{target}"
        current_branch = git("branch", "--show-current")
        unless ["main", branch].include?(current_branch)
          raise Error, "Start from main or #{branch} at origin/main"
        end
        progress "Checking GitHub authentication"
        run("gh", "auth", "status", "--hostname", "github.com")
        progress "Preparing #{branch}"
        if current_branch == "main"
          unless git("branch", "--list", branch).empty?
            unless git("rev-list", "--count", "origin/main..#{branch}") == "0"
              raise Error, "Existing #{branch} contains unmerged commits; review it before retrying"
            end
            git("branch", "-d", branch)
          end
          git("switch", "-c", branch)
        end
        Branch.check(@config.root)
        progress "Updating version and changelog to #{target}"
        File.write(file, text.sub(literal, %(VERSION = "#{target}")))
        run("git-cliff", "--config", "cliff.toml", "--unreleased", "--tag", "v#{target}", "--prepend", "CHANGELOG.md", live: true)
        progress "Updating Gemfile.lock"
        run("bundle", "lock", "--local", live: true)
        progress "Running verification (lint, tests, package, changelog)"
        run("bundle", "exec", "rake", "verify", live: true)
        files = [@config.data.fetch("version_file"), "CHANGELOG.md", "Gemfile.lock"]
        unless (git("diff", "--name-only").lines.map(&:strip) - files).empty? && git("ls-files", "--others", "--exclude-standard").empty?
          raise Error, "Verification changed unrelated files; review git diff before committing"
        end
        title = "chore(release): prepare v#{target}"
        body = "Prepare #{spec.name} #{target} for publication.\n\nRecord the version, generated notes and lockfile after verification."
        progress "Committing release metadata with hooks enabled"
        git("add", "--", *files)
        run("git", "commit", "-m", title, "-m", body, live: true)
        clean
        progress "Pushing #{branch}"
        run("git", "push", "--no-follow-tags", "--set-upstream", "origin", branch, live: true)
        progress "Opening release PR"
        url = run("gh", "pr", "create", "--repo", @config.data.fetch("repository"),
          "--base", "main", "--head", branch, "--title", title,
          "--body", "#{body}\n\nMerging this PR creates annotated tag v#{target} and publishes the verified gem.").strip
        "#{url}\nMerge this release PR to tag and publish v#{target}."
      end

      def verify(tag, tagged: true)
        clean
        raise Error, "Tag and gem version differ" unless tag == "v#{spec.version}"
        canonical_origin
        ref = "refs/tags/#{tag}"
        if tagged
          object = git("rev-parse", ref)
          raise Error, "Release tag must be annotated" unless git("cat-file", "-t", ref) == "tag"
          raise Error, "Tag must identify HEAD" unless git("rev-parse", "#{ref}^{}") == git("rev-parse", "HEAD")
          raise Error, "Canonical tag object differs" unless git("ls-remote", "--refs", "origin", ref).split.first == object
        end
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

      def canonical_origin
        origin = git("config", "--get", "remote.origin.url")
        repo = ENV.fetch("GITHUB_REPOSITORY", @config.data.fetch("repository"))
        unless ["https://github.com/#{repo}.git", "https://github.com/#{repo}", "git@github.com:#{repo}.git", "ssh://git@github.com/#{repo}.git"].include?(origin)
          raise Error, "Release origin must be the canonical GitHub repository"
        end
      end

      def clean
        status = git("status", "--porcelain")
        raise Error, "Release requires a clean working tree:\n#{status}" unless status.empty?
      end

      def git(*arguments)
        run("git", *arguments).strip
      end

      def progress(message)
        $stdout.puts "[release:prepare] #{message}..."
        $stdout.flush
      end

      def run(*arguments, live: false)
        environment = {"BUNDLE_GEMFILE" => File.join(@config.root, "Gemfile"),
                       "GEM_PATH" => [*Gem.path, *Gem.loaded_specs.values.map(&:base_dir)].uniq.join(File::PATH_SEPARATOR)}
        if live
          success = Bundler.with_unbundled_env { system(environment, *arguments, chdir: @config.root) }
          raise Error, "#{arguments.first(3).join(" ")} failed; see output above" unless success
          return ""
        end
        output, error, status = Bundler.with_unbundled_env { Open3.capture3(environment, *arguments, chdir: @config.root) }
        raise Error, "#{arguments.first(3).join(" ")} failed: #{output}#{error}" unless status.success?
        output
      end
    end
  end
end
