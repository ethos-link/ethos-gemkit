# frozen_string_literal: true

require_relative "test_helper"
require "ethos/gemkit/release"
require "ethos/gemkit/artifact"
require "minitest/mock"

class MemoryRegistry
  attr_reader :uploads

  def initialize
    @versions, @uploads = {}, []
  end

  def unused(version)
    raise Ethos::Gemkit::Error, "Registry already contains #{version}" if @versions.key?(version)
  end

  def version_info(version)
    @versions[version]
  end

  def push(file)
    @uploads << File.binread(file)
    spec = Gem::Package.new(file).spec
    @versions[spec.version.to_s] = {"sha" => Digest::SHA256.file(file).hexdigest}
  end
end

class ReleaseTest < GemkitTest
  TOOLKIT = File.expand_path("..", __dir__)

  def setup
    @directory = Dir.mktmpdir("gemkit-release-")
    @root = File.join(@directory, "repo")
    @origin = File.join(@directory, "origin.git")
    FileUtils.mkdir_p(File.join(@root, "lib/fixture"))
    @data = configuration.merge("metadata_files" => %w[lib/fixture/version.rb CHANGELOG.md Gemfile.lock UPGRADE.md])
    @config = Ethos::Gemkit::Configuration.new(@root, @data)
    @git = Ethos::Gemkit::Repository.new(@config, origin: @origin)
    @registry = MemoryRegistry.new
    @release = Ethos::Gemkit::Release.new(@config, repository: @git, registry: @registry)
    File.write(File.join(@root, ".ethos-gemkit.yml"), YAML.dump(@data))
    File.write(File.join(@root, "lib/fixture/version.rb"), "module Fixture\n  VERSION = \"0.1.0\"\nend\n")
    File.write(File.join(@root, "fixture.gemspec"), <<~SPEC)
      require_relative "lib/fixture/version"
      Gem::Specification.new do |s|
        s.name = "fixture"
        s.version = Fixture::VERSION
        s.summary = "Release fixture"
        s.authors = ["Test"]
        s.homepage = "https://example.test"
        s.license = "MIT"
        s.required_ruby_version = ">= 4.0"
        s.metadata["allowed_push_host"] = "https://rubygems.org"
        s.files = Dir["lib/**/*.rb", "CHANGELOG.md"]
      end
    SPEC
    File.write(File.join(@root, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gemspec
      gem "ethos-gemkit", path: #{TOOLKIT.inspect}, require: false
    GEMFILE
    File.write(File.join(@root, "Rakefile"), <<~RAKEFILE)
      require "bundler/setup"
      require "ethos/gemkit/tasks"
      task :test do
        abort "Simulated failed checks" if File.exist?(".git/fail-checks")
      end
    RAKEFILE
    File.write(File.join(@root, ".standard.yml"), "ruby_version: \"4.0\"\nplugins:\n  - ethos-gemkit\n")
    File.write(File.join(@root, ".gitignore"), "/pkg/\n")
    File.write(File.join(@root, "CHANGELOG.md"), "## [0.1.0]\n\n- Existing package.\n")
    File.write(File.join(@root, "UPGRADE.md"), "# Upgrading\n\n## Unreleased\n\nUse the updated fixture.\n")
    FileUtils.cp(File.join(TOOLKIT, "cliff.toml"), File.join(@root, "cliff.toml"))
    @git.git("init", "--bare", @origin)
    @git.git("init", "-b", "feature/initial")
    @git.git("config", "user.name", "Release Test")
    @git.git("config", "user.email", "release@example.invalid")
    @git.run("bundle", "lock", "--local")
    @git.git("add", ".")
    @git.git("commit", "-m", "feat: seed release fixture")
    @git.git("branch", "main")
    @git.git("tag", "-a", "v0.1.0", "-m", "Release v0.1.0")
    @git.git("remote", "add", "origin", @origin)
    @git.git("push", "origin", "main", "refs/tags/v0.1.0")
    File.write(File.join(@root, "README.md"), "Changed fixture\n")
    @git.git("add", ".")
    @git.git("commit", "-m", "feat: add fixture behavior")
    @git.git("switch", "main")
    @git.git("merge", "--ff-only", "feature/initial")
    @git.git("push", "origin", "main")
    {"pre-commit" => "guard", "commit-msg" => 'commitlint --message "$1"'}.each do |hook, command|
      path = File.join(@root, ".git/hooks", hook)
      File.write(path, "#!/bin/sh\nexec #{RbConfig.ruby} -I#{TOOLKIT}/lib #{TOOLKIT}/exe/ethos-gemkit #{command}\n")
      File.chmod(0o755, path)
    end
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def prepare
    @release.prepare("patch")
  end

  def test_staged_release_keeps_hooks_and_publishes_the_same_verified_artifact
    assert_includes prepare, "run release:tag"
    assert_equal "0.1.1", @release.current_version
    assert_equal "", @git.git("tag", "--list", "v0.1.1")
    assert File.exist?(@git.journal)
    assert_includes @release.tag, "Tagged and pushed"
    assert_equal @git.git("rev-parse", "HEAD"), @git.git("--git-dir", @origin, "rev-parse", "main")
    assert_equal "tag", @git.git("cat-file", "-t", "refs/tags/v0.1.1")
    assert @release.verify_tag("v0.1.1").include?("fixture behavior")
    record = Ethos::Gemkit::Artifact.build(@config, tag: "v0.1.1", notes: @release.verify_tag("v0.1.1"))
    artifact = Ethos::Gemkit::Artifact.new(File.join(@root, "pkg/release"))
    arguments = {repository: @data.fetch("repository"), tag: "v0.1.1", commit: record.fetch("commit"), name: "fixture", host: "https://rubygems.org", registry: @registry}
    assert_includes artifact.publish(**arguments), "Published"
    assert_equal Digest::SHA256.hexdigest(@registry.uploads.first), record.fetch("sha256")
    note_arguments = arguments.except(:registry)
    success = Struct.new(:success?).new(true)
    failure = Struct.new(:success?).new(false)
    Open3.stub(:capture3, ->(*args) { (args[1..2] == %w[release list]) ? ["[]", "", success] : ["", "notes failed", failure] }) do
      assert_raises(Ethos::Gemkit::Error) { artifact.publish_notes(**note_arguments) }
    end
    Open3.stub(:capture3, ->(*args) { (args[1..2] == %w[release list]) ? ["[]", "", success] : ["", "", success] }) do
      assert_includes artifact.publish_notes(**note_arguments), "Created GitHub release"
    end
    assert_raises(Ethos::Gemkit::Error) { artifact.verify(**note_arguments.merge(commit: "c" * 40)) }
    assert_raises(Ethos::Gemkit::Error) { artifact.verify(**note_arguments.merge(host: "https://other.example")) }
    assert_includes artifact.publish(**arguments), "recover notes only"
    assert_equal 1, @registry.uploads.size
    File.open(artifact.package_path, "ab") { |file| file.write("tampered") }
    assert_raises(Ethos::Gemkit::Error) { artifact.publish(**arguments) }
    assert_equal 1, @registry.uploads.size
    refute File.exist?(@git.journal)
  end

  def test_atomic_release_pushes_metadata_and_tag_together
    @data["release_mode"] = "atomic"
    File.write(File.join(@root, ".ethos-gemkit.yml"), YAML.dump(@data))
    # Configuration is committed through a feature branch before preparation.
    @git.git("switch", "-c", "feature/atomic")
    @git.git("add", ".ethos-gemkit.yml")
    @git.git("commit", "-m", "feat: configure atomic release")
    @git.git("switch", "main")
    @git.git("merge", "--ff-only", "feature/atomic")
    @git.git("push", "origin", "main")
    assert_includes prepare, "atomically pushed"
    assert_equal @git.git("rev-parse", "HEAD"), @git.git("--git-dir", @origin, "rev-parse", "v0.1.1^{}")
    assert @release.verify_tag("v0.1.1")
    refute File.exist?(@git.journal)
  end

  def test_resume_rejects_metadata_tampering
    prepare
    File.write(File.join(@root, "CHANGELOG.md"), "tampered")
    assert_raises(Ethos::Gemkit::Error) { @release.resume }
    assert_equal "", @git.git("tag", "--list", "v0.1.1")
  end

  def test_rejects_existing_tags_dirty_worktree_wrong_origin_and_feature_branches
    File.write(File.join(@root, "untracked"), "unfinished")
    assert_raises(Ethos::Gemkit::Error) { prepare }
    File.delete(File.join(@root, "untracked"))
    @git.git("switch", "-c", "feature/not-release")
    assert_raises(Ethos::Gemkit::Error) { prepare }
    @git.git("switch", "main")
    @git.git("tag", "v0.1.1")
    assert_raises(Ethos::Gemkit::Error) { prepare }
    @git.git("tag", "-d", "v0.1.1")
    @git.git("remote", "set-url", "--push", "origin", "/tmp/another-repository")
    assert_raises(Ethos::Gemkit::Error) { prepare }
    refute File.exist?(@git.journal)
  end

  def test_failed_checks_prevent_metadata_and_tag_mutation
    base = @git.git("rev-parse", "HEAD")
    File.write(File.join(@root, ".git/fail-checks"), "fail")
    assert_raises(Ethos::Gemkit::Error) { prepare }
    assert_equal base, @git.git("rev-parse", "HEAD")
    assert_equal "0.1.0", @release.current_version
    assert_equal "", @git.git("tag", "--list", "v0.1.1")
    refute File.exist?(@git.journal)
  end

  def test_resume_after_push_failure_keeps_the_same_metadata_commit
    original = @git.method(:run)
    failed = false
    @git.define_singleton_method(:run) do |*arguments, **options|
      if !failed && arguments.first(2) == %w[git push]
        failed = true
        raise Ethos::Gemkit::Error, "Simulated transport failure"
      end
      original.call(*arguments, **options)
    end
    assert_raises(Ethos::Gemkit::Error) { prepare }
    commit = @git.git("rev-parse", "HEAD")
    assert_includes @release.resume, "run release:tag"
    assert_equal commit, @git.git("rev-parse", "HEAD")
    assert_equal commit, @git.git("--git-dir", @origin, "rev-parse", "main")
    @release.tag
  end

  def test_tag_verification_rejects_overwritten_annotation
    prepare
    @release.tag
    @git.git("tag", "-f", "v0.1.1", "HEAD")
    error = assert_raises(Ethos::Gemkit::Error) { @release.verify_tag("v0.1.1") }
    assert_match "tag object", error.message
  end
end
