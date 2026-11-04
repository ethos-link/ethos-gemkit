# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "rubygems/package"
require_relative "registry"
require_relative "release"
require_relative "repository"

module Ethos
  module Gemkit
    class Artifact
      RECORD = "release.json"

      def self.build(config, tag:, notes:, directory: config.path("pkg/release"))
        repository = Repository.new(config)
        repository.clean
        record = {"schema" => 1, "repository" => config.data.fetch("repository"), "name" => config.name,
                  "tag" => tag, "commit" => repository.git("rev-parse", "HEAD"),
                  "tag_object" => repository.git("rev-parse", "refs/tags/#{tag}"),
                  "registry" => config.data.fetch("registry"), "toolkit_version" => VERSION,
                  "contract" => CONTRACT, "workflow_ref" => ENV.fetch("GITHUB_WORKFLOW_REF", "local-rehearsal")}
        unless repository.git("cat-file", "-t", "refs/tags/#{tag}") == "tag" && repository.git("rev-parse", "refs/tags/#{tag}^{}") == record.fetch("commit")
          raise Error, "Artifact must be built from the annotated release commit"
        end
        FileUtils.mkdir_p(directory)
        Dir.chdir(config.root) do
          spec = Gem::Specification.load("#{config.name}.gemspec")
          raise Error, "Gem version does not match verified tag" unless spec && "v#{spec.version}" == tag
          raise Error, "Package host differs from configuration" unless spec.metadata["allowed_push_host"] == record.fetch("registry").fetch("host")
          spec.files.each do |file|
            path = config.path(file)
            if File.symlink?(path) || repository.git("hash-object", "--no-filters", "--", path) != repository.git("rev-parse", "#{record.fetch("commit")}:#{file}")
              raise Error, "Package file differs from the release commit: #{file}"
            end
          end
          repository.clean
          raise Error, "Release checkout changed during package evaluation" unless repository.git("rev-parse", "HEAD") == record.fetch("commit")
          record["version"], record["platform"] = spec.version.to_s, spec.platform.to_s
          record["file"] = "#{spec.full_name}.gem"
          Gem::Package.build(spec, false, false, File.join(directory, record.fetch("file")))
        end
        File.write(File.join(directory, "release-notes.md"), notes)
        record["sha256"] = Digest::SHA256.file(File.join(directory, record.fetch("file"))).hexdigest
        record["notes_sha256"] = Digest::SHA256.hexdigest(notes)
        File.write(File.join(directory, RECORD), JSON.pretty_generate(record))
        new(directory).verify(repository: record.fetch("repository"), tag: tag, commit: record.fetch("commit"))
        record
      end

      attr_reader :record, :directory

      def initialize(directory)
        @directory = File.realpath(directory)
        raise Error, "Artifact record must not be a symlink" if File.symlink?(File.join(@directory, RECORD))
        @record = JSON.parse(File.read(File.join(@directory, RECORD)))
        raise Error, "Artifact record must be a mapping" unless @record.is_a?(Hash)
      rescue Errno::ENOENT, JSON::ParserError
        raise Error, "Missing or invalid release artifact record"
      end

      def verify(repository:, tag:, commit:, name: nil, host: nil)
        unless record["schema"] == 1 && record["contract"] == CONTRACT &&
            record["repository"] == repository && record["tag"] == tag && record["commit"] == commit &&
            tag == "v#{record.fetch("version")}" && record.fetch("version").match?(Release::VERSION_PATTERN) &&
            record.fetch("commit").match?(/\A[0-9a-f]{40}\z/) && record.fetch("tag_object").match?(/\A[0-9a-f]{40}\z/)
          raise Error, "Artifact provenance does not match the requested release"
        end
        raise Error, "Unexpected gem name" if name && record["name"] != name
        raise Error, "Unexpected registry host" if host && record.fetch("registry")["host"] != host
        Registry.new(**record.fetch("registry").transform_keys(&:to_sym), name: record.fetch("name"))
        file = package_path
        raise Error, "Artifact digest differs from release record" unless Digest::SHA256.file(file).hexdigest == record.fetch("sha256")
        package = Gem::Package.new(file)
        package.verify
        spec = package.spec
        unless spec.name == record.fetch("name") && spec.version.to_s == record.fetch("version") &&
            spec.platform.to_s == record.fetch("platform") && spec.metadata["allowed_push_host"] == record.fetch("registry").fetch("host")
          raise Error, "Package metadata differs from verified release record"
        end
        raise Error, "Release notes must not be a symlink" if File.symlink?(File.join(directory, "release-notes.md"))
        unless Digest::SHA256.file(File.join(directory, "release-notes.md")).hexdigest == record.fetch("notes_sha256")
          raise Error, "Release notes differ from the verified artifact"
        end
        true
      rescue KeyError, Errno::ENOENT, Gem::Package::Error => error
        raise Error, "Invalid release artifact: #{error.message}"
      end

      def publish(repository:, tag:, commit:, name:, host:, registry: nil)
        verify(repository: repository, tag: tag, commit: commit, name: name, host: host)
        registry ||= Registry.new(**record.fetch("registry").transform_keys(&:to_sym), name: name)
        existing = registry.version_info(record.fetch("version"))
        if existing
          unless existing["sha"] == record.fetch("sha256")
            raise Error, "Existing registry version has an unverified or different digest; do not republish"
          end
          return "Package already published with the verified digest; recover notes only"
        end
        registry.push(package_path)
        published = nil
        5.times do
          published = registry.version_info(record.fetch("version"))
          break if published
          sleep 2
        end
        unless published && published["sha"] == record.fetch("sha256")
          raise Error, "Upload outcome is not confirmed; reconcile the registry before retrying"
        end
        File.write(File.join(directory, "publication.json"), JSON.pretty_generate(record.slice("name", "version", "sha256", "tag", "commit")))
        "Published #{name} #{record.fetch("version")} with the verified digest"
      end

      def publish_notes(repository:, tag:, commit:, name:, host:)
        verify(repository: repository, tag: tag, commit: commit, name: name, host: host)
        output, _, status = Open3.capture3("gh", "release", "list", "--repo", repository, "--limit", "1000", "--json", "tagName")
        raise Error, "Cannot inspect GitHub releases" unless status.success?
        if JSON.parse(output).any? { |release| release.fetch("tagName") == tag }
          output, _, status = Open3.capture3("gh", "release", "view", tag, "--repo", repository, "--json", "body")
          unless status.success? && JSON.parse(output).fetch("body").strip == File.read(File.join(directory, "release-notes.md")).strip
            raise Error, "Existing GitHub release notes differ; reconcile manually"
          end
          return "GitHub release notes already match"
        end
        _, _, status = Open3.capture3("gh", "release", "create", tag, package_path,
          "--repo", repository, "--verify-tag", "--target", commit, "--title", tag,
          "--notes-file", File.join(directory, "release-notes.md"))
        raise Error, "GitHub release failed; retry notes using the same artifact" unless status.success?
        "Created GitHub release #{tag}"
      end

      def package_path
        filename = record.fetch("file")
        unless filename.is_a?(String) && filename == File.basename(filename) && filename.end_with?(".gem")
          raise Error, "Artifact filename must be a gem basename"
        end
        path = File.join(directory, filename)
        raise Error, "Artifact must not be a symlink" if File.symlink?(path)
        path
      end
    end
  end
end
