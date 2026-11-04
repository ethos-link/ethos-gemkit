# frozen_string_literal: true

require_relative "test_helper"
require "ethos/gemkit/release"
require "rubygems/package"

class ReleaseTest < GemkitTest
  TOOLKIT = File.expand_path("..", __dir__)

  def setup
    @directory = Dir.mktmpdir("gemkit-release-")
    @root, @origin = File.join(@directory, "repo"), File.join(@directory, "origin.git")
    FileUtils.mkdir_p(File.join(@root, "lib/fixture"))
    File.write(File.join(@root, "lib/fixture/version.rb"), "module Fixture\n  VERSION = \"0.1.0\"\nend\n")
    File.write(File.join(@root, "fixture.gemspec"), <<~SPEC)
      require_relative "lib/fixture/version"
      Gem::Specification.new do |s|
        s.name = "fixture"
        s.version = Fixture::VERSION
        s.authors = ["Test"]
        s.summary = "Release fixture"
        s.license = "MIT"
        s.homepage = "https://example.test"
        s.required_ruby_version = ">= 4.0"
        s.metadata["allowed_push_host"] = "https://rubygems.org"
        s.files = Dir["lib/**/*.rb", "CHANGELOG.md"]
      end
    SPEC
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\ngemspec\ngem \"ethos-gemkit\", path: #{TOOLKIT.inspect}, require: false\n")
    File.write(File.join(@root, "Rakefile"), "require \"rake\"\ntask :test\nrequire \"ethos/gemkit/rake\"\n")
    File.write(File.join(@root, ".standard.yml"), "ruby_version: \"4.0\"\nplugins:\n  - ethos-gemkit\n")
    File.write(File.join(@root, ".gitignore"), "/pkg/\n")
    File.write(File.join(@root, "CHANGELOG.md"), "## [0.1.0]\n\n- Existing package.\n")
    FileUtils.cp(File.join(TOOLKIT, "cliff.toml"), File.join(@root, "cliff.toml"))
    command("git", "init", "--bare", @origin)
    git("init", "-b", "feature/release")
    git("config", "user.name", "Release Test")
    git("config", "user.email", "release@example.invalid")
    command("bundle", "lock", "--local")
    git("add", ".")
    git("commit", "-m", "feat: seed fixture")
    git("branch", "main")
    git("tag", "-a", "v0.1.0", "-m", "Release v0.1.0")
    git("config", "url.#{@origin}.insteadOf", "https://github.com/ethos-link/fixture.git")
    git("remote", "add", "origin", "https://github.com/ethos-link/fixture.git")
    git("push", "--no-follow-tags", "origin", "main", "refs/tags/v0.1.0")
    {"pre-commit" => "guard", "commit-msg" => 'commitlint --message "$1"'}.each do |hook, action|
      path = File.join(@root, ".git/hooks", hook)
      File.write(path, "#!/bin/sh\nexec #{RbConfig.ruby} -I#{TOOLKIT}/lib #{TOOLKIT}/exe/ethos-gemkit #{action}\n")
      File.chmod(0o755, path)
    end
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def command(*arguments, success: true, environment: {})
    output, error, status = capture(@root, *arguments, environment: {"GITHUB_REPOSITORY" => "ethos-link/fixture"}.merge(environment))
    assert_equal success, status.success?, output + error
    output + error
  end

  def git(*arguments)
    command("git", *arguments).strip
  end

  def verify(success: true)
    command("bundle", "exec", "ruby", "-rethos/gemkit/release", "-e",
      'Ethos::Gemkit::Release.new(Ethos::Gemkit::Configuration.load).verify("v0.1.0")', success: success)
  end

  def test_prepare_uses_a_normal_reviewed_commit_and_native_tag_build
    File.write(File.join(@root, "README.md"), "New behavior\n")
    git("add", ".")
    git("commit", "-m", "feat: add fixture behavior")
    before = git("rev-parse", "HEAD")
    output = command("bundle", "exec", "rake", "release:prepare[patch]")
    assert_includes output, "review git diff"
    assert_equal before, git("rev-parse", "HEAD")
    assert_empty git("tag", "--list", "v0.1.1")
    assert_includes File.read(File.join(@root, "CHANGELOG.md")), "- Existing package."
    command("bundle", "lock", "--local")
    git("add", ".")
    git("commit", "-m", "chore(release): prepare v0.1.1")
    git("switch", "main")
    git("merge", "--ff-only", "feature/release")
    git("tag", "-a", "v0.1.1", "-m", "Release v0.1.1")
    git("push", "--no-follow-tags", "origin", "main", "refs/tags/v0.1.1")
    command("bundle", "exec", "rake", "release:build", environment: {"RELEASE_TAG" => "v0.1.1"})
    package = File.join(@root, "pkg/fixture-0.1.1.gem")
    assert_equal "0.1.1", Gem::Package.new(package).spec.version.to_s
    assert_empty git("status", "--porcelain")
    assert_empty Dir[File.join(@root, ".git/*gemkit*")]
    exercise_publication_and_notes(File.dirname(package))
  end

  def test_verifier_rejects_dirty_worktrees_lightweight_and_replaced_tags
    verify
    File.write(File.join(@root, "unfinished"), "unfinished")
    assert_includes verify(success: false), "clean working tree"
    File.delete(File.join(@root, "unfinished"))
    git("tag", "-d", "v0.1.0")
    git("tag", "v0.1.0")
    assert_includes verify(success: false), "annotated"
    git("tag", "-f", "-a", "v0.1.0", "-m", "Replaced annotation")
    assert_includes verify(success: false), "Canonical tag object differs"
  end

  def test_verifier_rejects_wrong_origins_non_main_commits_and_ignored_package_files
    git("remote", "set-url", "origin", "https://github.com/other/fixture.git")
    assert_includes verify(success: false), "canonical GitHub"
    git("remote", "set-url", "origin", "https://github.com/ethos-link/fixture.git")
    File.write(File.join(@root, ".git/info/exclude"), "lib/fixture/hidden.rb\n")
    File.write(File.join(@root, "lib/fixture/hidden.rb"), "Hidden bytes\n")
    verify(success: false)
    File.delete(File.join(@root, "lib/fixture/hidden.rb"))
    File.write(File.join(@root, "README.md"), "Unmerged\n")
    git("add", ".")
    git("commit", "-m", "feat: unmerged behavior")
    git("tag", "-f", "-a", "v0.1.0", "-m", "Unmerged release")
    git("push", "--force", "origin", "refs/tags/v0.1.0") # Disposable registry only.
    verify(success: false)
  end

  def test_main_branch_has_no_release_bypass
    git("switch", "main")
    output = command("bundle", "exec", "rake", "release:prepare[patch]", success: false,
      environment: {"ETHOS_GEMKIT_RELEASE_VERSION" => "0.1.1"})
    assert_includes output, "feature branch"
    assert_empty git("status", "--porcelain")
  end

  def exercise_publication_and_notes(directory)
    workflow = YAML.safe_load_file(File.join(TOOLKIT, ".github/workflows/release.yml"))
    publish = workflow.fetch("jobs").fetch("publish").fetch("steps").last.fetch("run")
    notes = workflow.fetch("jobs").fetch("notes").fetch("steps").last.fetch("run")
    bin = File.join(@directory, "bin")
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, "gem"), "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$UPLOAD_LOG\"\ncp \"$2\" \"$REGISTRY_FILE\"\n")
    File.write(File.join(bin, "gh"), "#!/bin/sh\ntest ! -f \"$FAIL_NOTES\"\n")
    FileUtils.chmod(0o755, Dir[File.join(bin, "*")])
    environment = {"PATH" => "#{bin}:#{ENV.fetch("PATH")}", "GEM_FILE" => "fixture-0.1.1.gem",
                   "GEM_HOST" => "https://rubygems.org", "RELEASE_TAG" => "v0.1.1", "UPLOAD_LOG" => File.join(@directory, "uploads"),
                   "REGISTRY_FILE" => File.join(@directory, "published.gem"), "FAIL_NOTES" => File.join(@directory, "fail-notes")}
    run = ->(script) { Open3.capture3(environment, "bash", "-euo", "pipefail", "-c", script, chdir: directory).last.success? }
    assert run.call("sha256sum --check --strict SHA256SUMS\n#{publish}")
    assert_equal File.binread(File.join(directory, environment.fetch("GEM_FILE"))), File.binread(environment.fetch("REGISTRY_FILE"))
    File.write(environment.fetch("FAIL_NOTES"), "fail")
    refute run.call("sha256sum --check --strict SHA256SUMS\n#{notes}")
    File.delete(environment.fetch("FAIL_NOTES"))
    assert run.call("sha256sum --check --strict SHA256SUMS\n#{notes}")
    assert_equal 1, File.readlines(environment.fetch("UPLOAD_LOG")).size
    File.open(File.join(directory, environment.fetch("GEM_FILE")), "ab") { |file| file.write("tampered") }
    refute run.call("sha256sum --check --strict SHA256SUMS\n#{publish}")
    assert_equal 1, File.readlines(environment.fetch("UPLOAD_LOG")).size
  end
end
