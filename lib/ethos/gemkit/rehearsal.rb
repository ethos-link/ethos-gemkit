# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "shellwords"
require_relative "release"
require_relative "artifact"

module Ethos
  module Gemkit
    # All Git mutations and uploads are confined to disposable local fixtures.
    class Rehearsal
      class Registry
        attr_reader :uploads

        def initialize
          @versions, @uploads = {}, []
        end

        def unused(version)
          raise Error, "Rehearsal version already exists" if version_info(version)
        end

        def version_info(version)
          @versions[version]
        end

        def push(file)
          @uploads << Digest::SHA256.file(file).hexdigest
          @versions[Gem::Package.new(file).spec.version.to_s] = {"sha" => @uploads.last}
        end
      end

      def initialize(config)
        @source = config
      end

      def run
        toolkit = File.expand_path("../../..", __dir__)
        Dir.mktmpdir("ethos-gemkit-rehearsal-") do |directory|
          root = File.join(directory, "repo")
          FileUtils.mkdir_p(root)
          source = Repository.new(@source)
          source.git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split("\0").uniq.each do |file|
            next if file.start_with?("pkg/", "tmp/")
            path = @source.path(file)
            next unless File.file?(path)
            destination = File.join(root, file)
            FileUtils.mkdir_p(File.dirname(destination))
            FileUtils.cp(path, destination, preserve: true)
          end
          # The dependency is deliberately local only in this disposable copy.
          gemfile = File.join(root, "Gemfile")
          text = File.read(gemfile)
          text = text.lines.reject { |line| line.match?(/^\s*(?:gemkit_source =|gem "ethos-gemkit",)/) }.join
          File.write(gemfile, text + "\ngem \"ethos-gemkit\", path: #{toolkit.inspect}, require: false\n")
          FileUtils.rm_f(File.join(root, "Gemfile.lock"))
          config = Configuration.load(root)
          origin = File.join(directory, "origin.git")
          git = Repository.new(config, origin: origin)
          git.git("init", "--bare", origin)
          git.git("init", "-b", "feature/rehearsal")
          git.git("config", "user.name", "Gemkit Rehearsal")
          git.git("config", "user.email", "rehearsal@example.invalid")
          git.run("bundle", "lock", "--local", environment: {"BUNDLE_FROZEN" => "false", "BUNDLE_DEPLOYMENT" => "false"})
          git.git("add", ".")
          git.git("commit", "-m", "feat: snapshot consumer for release rehearsal")
          git.git("branch", "main")
          git.git("remote", "add", "origin", origin)
          git.git("push", "origin", "main")
          git.git("switch", "main")
          {"pre-commit" => "guard", "commit-msg" => 'commitlint --message "$1"'}.each do |hook, command|
            path = File.join(root, ".git/hooks", hook)
            File.write(path, "#!/bin/sh\nexec #{Shellwords.escape(RbConfig.ruby)} -I#{Shellwords.escape(File.join(toolkit, "lib"))} #{Shellwords.escape(File.join(toolkit, "exe/ethos-gemkit"))} #{command}\n")
            File.chmod(0o755, path)
          end
          registry = Registry.new
          release = Release.new(config, repository: git, registry: registry)
          version = release.next_version("patch")
          release.prepare("patch")
          release.tag if config.data.fetch("release_mode") == "staged"
          tag = "v#{version}"
          notes = release.verify_tag(tag)
          File.write(File.join(root, ".git/notes.md"), notes)
          git.run(RbConfig.ruby, "-I", File.join(toolkit, "lib"), "-rethos/gemkit/artifact", "-e", <<~BUILD, tag)
            config = Ethos::Gemkit::Configuration.load
            Ethos::Gemkit::Artifact.build(config, tag: ARGV.fetch(0), notes: File.read(".git/notes.md"))
          BUILD
          artifact = Artifact.new(File.join(root, "pkg/release"))
          arguments = {repository: config.data.fetch("repository"), tag: tag, commit: git.git("rev-parse", "HEAD"),
                       name: config.name, host: config.data.fetch("registry").fetch("host"), registry: registry}
          artifact.publish(**arguments)
          # A failed notes step must be recoverable without a second upload.
          artifact.publish(**arguments)
          raise Error, "Rehearsal uploaded more than once" unless registry.uploads == [artifact.record.fetch("sha256")]
          git.clean
          "Release rehearsal passed for #{config.name}: hooks, checks, metadata, annotated tag, exact artifact and publication retry (one local upload)"
        end
      end
    end
  end
end
