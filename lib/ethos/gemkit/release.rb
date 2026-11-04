# frozen_string_literal: true

require "json"
require "tmpdir"
require "digest"
require "bundler"
require_relative "repository"
require_relative "registry"
require_relative "commit_message"

module Ethos
  module Gemkit
    class Release
      VERSION_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
      VERSION_LINE = /VERSION = "([^"\n]+)"/

      attr_reader :repository, :config

      def initialize(config, repository: Repository.new(config), registry: Registry.for(config))
        required = [config.data.fetch("version_file"), "CHANGELOG.md", "Gemfile.lock"]
        unless (required - config.data.fetch("metadata_files")).empty?
          raise Error, "Release metadata_files must include version_file, CHANGELOG.md and Gemfile.lock"
        end
        @config, @repository, @registry = config, repository, registry
      end

      def current_version
        match = File.read(config.path(config.data.fetch("version_file"))).match(VERSION_LINE)
        raise Error, "Cannot find a literal VERSION in the configured version file" unless match && match[1].match?(VERSION_PATTERN)
        match[1]
      end

      def next_version(target)
        major, minor, patch = current_version.split(".").map(&:to_i)
        version = case target
        when "major" then "#{major + 1}.0.0"
        when "minor" then "#{major}.#{minor + 1}.0"
        when "patch" then "#{major}.#{minor}.#{patch + 1}"
        else target.to_s
        end
        unless version.match?(VERSION_PATTERN) && Gem::Version.new(version) > Gem::Version.new(current_version)
          raise Error, "Use patch, minor, major or a strictly newer X.Y.Z version"
        end
        CommitMessage.validate(message(version))
        version
      end

      def prepare(target)
        raise Error, "Unfinished release: use release:resume" if File.exist?(repository.journal)
        version = next_version(target)
        repository.main
        repository.clean
        require_unused_tag(version)
        @registry.unused(version)
        verify
        @state = {"schema" => 1, "version" => version, "base" => repository.git("rev-parse", "HEAD"),
                  "stage" => "metadata", "configuration" => identity}
        save
        before = File.read(config.path("CHANGELOG.md"))
        version_path = config.path(config.data.fetch("version_file"))
        File.write(version_path, File.read(version_path).sub(VERSION_LINE, "VERSION = \"#{version}\""))
        repository.run("git-cliff", "-c", "cliff.toml", "--unreleased", "--tag", "v#{version}", "--prepend", "CHANGELOG.md")
        preserve_history(before, File.read(config.path("CHANGELOG.md")))
        notes(version)
        promote_upgrade(version)
        pins = dependency_pins(File.read(config.path("Gemfile.lock")))
        repository.run("bundle", "lock", "--local", environment: {"BUNDLE_FROZEN" => "false", "BUNDLE_DEPLOYMENT" => "false"})
        unless dependency_pins(File.read(config.path("Gemfile.lock"))) == pins
          raise Error, "Dependency pins changed; inspect metadata before recovery"
        end
        @state["hashes"] = files.to_h { |file| [file, Digest::SHA256.file(config.path(file)).hexdigest] }
        @state["stage"] = "ready"
        save
        finish
      end

      def resume
        load_state
        raise Error, "Metadata preparation was interrupted; inspect and restore metadata manually" if @state.fetch("stage") == "metadata"
        repository.main(current: false)
        unchanged_metadata
        finish
      end

      def tag
        repository.main
        repository.clean
        version = current_version
        @registry.unused(version)
        verify
        validate_commit(version)
        repository.main
        tag = "v#{version}"
        expected = repository.git("rev-parse", "HEAD")
        existing = repository.remote_tag(tag)
        if existing
          local = repository.git("rev-parse", "refs/tags/#{tag}")
          raise Error, "Conflicting remote tag" unless local == existing
          verify_tag(tag)
          clear_journal
          return "#{tag} is already on origin; recover publication through CI"
        end
        if repository.success?("git", "rev-parse", "--verify", "refs/tags/#{tag}")
          unless repository.git("cat-file", "-t", "refs/tags/#{tag}") == "tag" && repository.git("rev-parse", "refs/tags/#{tag}^{}") == expected
            raise Error, "Existing local tag conflicts with the prepared release"
          end
        else
          repository.git("tag", "-a", tag, "-m", "Release #{tag}")
        end
        repository.git("push", "--no-follow-tags", "origin", "refs/tags/#{tag}:refs/tags/#{tag}")
        raise Error, "Remote tag identity differs after push" unless repository.remote_tag(tag) == repository.git("rev-parse", "refs/tags/#{tag}")
        clear_journal
        "Tagged and pushed #{tag}; GitHub Actions publishes"
      end

      def verify
        repository.run("bundle", "exec", "rake", "verify")
        repository.run("git-cliff", "--config", "cliff.toml", "--unreleased", "--output", File.join(Dir.tmpdir, "gemkit-cliff-#{Process.pid}.md"))
        true
      end

      def verify_tag(tag)
        raise Error, "Tag and gem version differ" unless tag == "v#{current_version}"
        repository.validate_origin
        repository.fetch_main
        remote = repository.remote_tag(tag)
        raise Error, "Release tag is missing on origin" unless remote
        canonical = "refs/ethos-gemkit/tags/#{tag}"
        repository.git("fetch", "--no-tags", "origin", "refs/tags/#{tag}:#{canonical}")
        unless repository.git("rev-parse", canonical) == remote && repository.git("rev-parse", "refs/tags/#{tag}") == remote
          raise Error, "Local release tag differs from the canonical tag object"
        end
        raise Error, "Release tag must be annotated" unless repository.git("cat-file", "-t", canonical) == "tag"
        unless repository.git("rev-parse", "#{canonical}^{}") == repository.git("rev-parse", "HEAD")
          raise Error, "Tag must identify the checked-out release commit"
        end
        unless repository.success?("git", "merge-base", "--is-ancestor", "HEAD", "origin/main")
          raise Error, "Release commit must belong to origin/main"
        end
        validate_commit(current_version)
        notes(current_version)
      end

      def guard_staged(version)
        load_state
        unless @state.fetch("stage") == "ready" && @state.fetch("version") == version && repository.git("rev-parse", "HEAD") == @state.fetch("base")
          raise Error, "No matching prepared release journal for this metadata commit"
        end
        changed = repository.git("diff", "--cached", "--name-only", "-z").split("\0")
        validate_files(changed)
        @state.fetch("hashes").each do |file, hash|
          staged = repository.run("git", "show", ":#{file}")
          raise Error, "Staged release metadata was modified: #{file}" unless Digest::SHA256.hexdigest(staged) == hash
        end
        unchanged_metadata
        validate_metadata(version, "HEAD", changed, ->(file) { repository.run("git", "show", ":#{file}") })
        true
      end

      private

      def files
        config.data.fetch("metadata_files")
      end

      def identity
        config.data.slice("gem_name", "repository", "version_file", "metadata_files", "release_mode")
      end

      def load_state
        @state = JSON.parse(File.read(repository.journal))
        unless @state["schema"] == 1 && @state["configuration"] == identity && @state["version"].to_s.match?(VERSION_PATTERN)
          raise Error, "Release journal does not match repository configuration"
        end
      rescue Errno::ENOENT, JSON::ParserError, KeyError
        raise Error, "No valid release journal exists"
      end

      def unchanged_metadata
        unless @state.fetch("hashes").keys.sort == files.sort
          raise Error, "Release journal contains unexpected metadata paths"
        end
        @state.fetch("hashes").each do |file, hash|
          raise Error, "Release metadata changed: #{file}" unless Digest::SHA256.file(config.path(file)).hexdigest == hash
        end
      end

      def finish
        unchanged_metadata
        head = repository.git("rev-parse", "HEAD")
        if head == @state.fetch("base")
          changed = repository.git("diff", "--name-only", "HEAD", "-z").split("\0")
          validate_files(changed)
          raise Error, "Remove unrelated untracked files before resuming" unless repository.git("ls-files", "--others", "--exclude-standard").empty?
          verify
          message_path = repository.journal + ".message"
          File.write(message_path, message(@state.fetch("version")))
          repository.git("add", "--", *files)
          repository.run("git", "commit", "-F", message_path, environment: {"ETHOS_GEMKIT_RELEASE_VERSION" => @state.fetch("version")})
          @state["commit"] = repository.git("rev-parse", "HEAD")
          @state["stage"] = "committed"
          save
        end
        repository.clean
        unless repository.git("rev-parse", "HEAD^") == @state.fetch("base")
          raise Error, "Unexpected commit while a release is pending"
        end
        validate_commit(@state.fetch("version"))
        if config.data.fetch("release_mode") == "atomic"
          tag = "v#{@state.fetch("version")}"
          existing = repository.remote_tag(tag)
          if existing
            unless repository.git("rev-parse", "refs/tags/#{tag}") == existing
              raise Error, "Conflicting remote tag during recovery"
            end
            verify_tag(tag)
          else
            if repository.success?("git", "rev-parse", "--verify", "refs/tags/#{tag}")
              unless repository.git("cat-file", "-t", "refs/tags/#{tag}") == "tag" && repository.git("rev-parse", "refs/tags/#{tag}^{}") == repository.git("rev-parse", "HEAD")
                raise Error, "Conflicting local tag"
              end
            else
              repository.git("tag", "-a", tag, "-m", "Release #{tag}")
            end
            repository.git("push", "--no-follow-tags", "--atomic", "origin", "HEAD:refs/heads/main", "refs/tags/#{tag}:refs/tags/#{tag}")
          end
          clear_journal
          "Prepared and atomically pushed #{tag}; GitHub Actions publishes"
        else
          repository.git("push", "--no-follow-tags", "origin", "HEAD:refs/heads/main")
          @state["stage"] = "staged"
          save
          "Prepared v#{@state.fetch("version")}; run release:tag after reviewing metadata"
        end
      end

      def validate_commit(version)
        raise Error, "Tag must identify a prepared release commit" unless repository.git("log", "-1", "--format=%s") == message(version).lines.first.strip
        raise Error, "Release commits must have exactly one parent" unless repository.git("rev-list", "--parents", "-n", "1", "HEAD").split.size == 2
        changed = repository.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD", "-z").split("\0")
        validate_files(changed)
        validate_metadata(version, "HEAD^", changed, ->(file) { File.read(config.path(file)) })
        notes(version)
      end

      def validate_metadata(version, before_ref, changed, after)
        file = config.data.fetch("version_file")
        prior = repository.run("git", "show", "#{before_ref}:#{file}")
        expected = prior.sub(VERSION_LINE, "VERSION = \"#{version}\"")
        unless after.call(file) == expected && Gem::Version.new(version) > Gem::Version.new(prior.match(VERSION_LINE)[1])
          raise Error, "Version file may only increase its literal VERSION"
        end
        preserve_history(repository.run("git", "show", "#{before_ref}:CHANGELOG.md"), after.call("CHANGELOG.md"))
        unless dependency_pins(repository.run("git", "show", "#{before_ref}:Gemfile.lock")) == dependency_pins(after.call("Gemfile.lock"))
          raise Error, "Release commit changed dependency pins"
        end
        if changed.include?("UPGRADE.md")
          before = repository.run("git", "show", "#{before_ref}:UPGRADE.md")
          unless after.call("UPGRADE.md") == promoted_upgrade(before, version)
            raise Error, "Upgrade notes may only promote the pending section"
          end
        end
        own_spec = Bundler::LockfileParser.new(after.call("Gemfile.lock")).specs.find { |spec| spec.name == config.name }
        raise Error, "Lockfile gem version differs from release" unless own_spec&.version.to_s == version
      end

      def validate_files(changed)
        required = [config.data.fetch("version_file"), "CHANGELOG.md", "Gemfile.lock"]
        unless (required - changed).empty? && (changed - files).empty?
          raise Error, "Release commit must contain only configured release metadata, including version, changelog and lockfile"
        end
      end

      def dependency_pins(text)
        # Preserve sources, Git revisions, platforms and transitive constraints,
        # allowing only the consumer's own version to change.
        Bundler::LockfileParser.new(text)
        text.gsub(/^((?:  |    )#{Regexp.escape(config.name)}) \([^\n)]+\)$/, '\\1 (RELEASE_VERSION)')
      end

      def preserve_history(before, after)
        history = before.lines.drop_while { |line| !line.start_with?("## ") }.join.rstrip
        raise Error, "Changelog history changed" unless history.empty? || after.rstrip.end_with?(history)
      end

      def notes(version)
        entry = File.read(config.path("CHANGELOG.md")).split(/^## /).find { |section| section.lines.first.to_s.strip.match?(/\A\[#{Regexp.escape(version)}\](?: - .*)?\z/) }
        raise Error, "Missing meaningful changelog entry for #{version}" unless entry.to_s.lines.any? { |line| line.start_with?("- ") }
        "## #{entry}"
      end

      def promoted_upgrade(before, version)
        before.sub(/^## (?:Unreleased|Next)$/, "## [#{version}]")
      end

      def promote_upgrade(version)
        return unless files.include?("UPGRADE.md")
        path = config.path("UPGRADE.md")
        before = File.read(path)
        File.write(path, promoted_upgrade(before, version))
      end

      def message(version)
        "chore(release): prepare v#{version}\n\nWhat: Record the verified version and generated release notes.\nWhy: Publish verified changes as an immutable package.\nWhere: Release metadata for #{config.name}.\n"
      end

      def require_unused_tag(version)
        tag = "v#{version}"
        raise Error, "Release tag already exists locally" if repository.success?("git", "rev-parse", "--verify", "refs/tags/#{tag}")
        raise Error, "Release tag already exists on origin" if repository.remote_tag(tag)
      end

      def save
        temporary = repository.journal + ".tmp"
        File.write(temporary, JSON.pretty_generate(@state))
        File.rename(temporary, repository.journal)
      end

      def clear_journal
        [repository.journal, repository.journal + ".message"].each { |path| File.delete(path) if File.exist?(path) }
      end
    end
  end
end
