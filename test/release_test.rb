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
    FileUtils.cp(File.join(TOOLKIT, ".gitignore"), File.join(@root, ".gitignore"))
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
    @bin = File.join(@directory, "bin")
    FileUtils.mkdir_p(@bin)
    File.write(File.join(@bin, "gh"), <<~SH)
      #!/bin/sh
      if [ "$1" = auth ]; then exit 0; fi
      printf '%s\\n' "$*" >> "$PR_LOG"
      printf '%s\\n' 'https://github.com/ethos-link/fixture/pull/1'
    SH
    File.chmod(0o755, File.join(@bin, "gh"))
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
    output, error, status = capture(@root, *arguments, environment: {"GITHUB_REPOSITORY" => "ethos-link/fixture", "PATH" => "#{@bin}:#{ENV.fetch("PATH")}", "PR_LOG" => File.join(@directory, "pull-request")}.merge(environment))
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

  def test_prepare_from_main_opens_a_verified_release_pr_and_merge_build_tags_and_publishes
    File.write(File.join(@root, "README.md"), "New behavior\n")
    git("add", ".")
    git("commit", "-m", "feat: add fixture behavior")
    git("switch", "main")
    git("merge", "--ff-only", "feature/release")
    git("push", "--no-follow-tags", "origin", "main")
    git("config", "push.followTags", "true")
    git("tag", "-a", "local-backup", "-m", "Unrelated tag")
    before = git("rev-parse", "HEAD")
    git("branch", "chore/release-v0.1.1", "v0.1.0^{}") # Already merged preparation from a failed release.
    output = command("bundle", "exec", "rake", "release:prepare[patch]")
    assert_includes output, "https://github.com/ethos-link/fixture/pull/1"
    assert_includes output, "Merge this release PR"
    assert_equal "chore/release-v0.1.1", git("branch", "--show-current")
    assert_match(/^  standard \([^)]+\) sha256=[a-f0-9]{64}$/, File.read(File.join(@root, "Gemfile.lock")))
    assert_equal "chore(release): prepare v0.1.1", git("log", "-1", "--format=%s")
    assert_equal before, git("rev-parse", "main")
    assert_equal before, git("--git-dir", @origin, "rev-parse", "main")
    assert_empty git("tag", "--list", "v0.1.1")
    assert_includes File.read(File.join(@root, "CHANGELOG.md")), "- Existing package."
    assert_includes File.read(File.join(@directory, "pull-request")), "--base main --head chore/release-v0.1.1"
    git("switch", "main")
    git("merge", "--ff-only", "chore/release-v0.1.1")
    git("push", "--no-follow-tags", "origin", "main")
    FileUtils.mkdir_p(File.join(@root, "vendor/bundle"))
    File.write(File.join(@root, "vendor/bundle/cached-gem"), "CI dependency cache\n")
    command("bundle", "exec", "rake", "release:build", environment: {"RELEASE_TAG" => "v0.1.1", "RELEASE_FROM_PR" => "true"})
    workflow = YAML.safe_load_file(File.join(TOOLKIT, ".github/workflows/release.yml"))
    tag = workflow.fetch("jobs").fetch("tag").fetch("steps").last.fetch("run")
    environment = {"RELEASE_TAG" => "v0.1.1", "RELEASE_COMMIT" => git("rev-parse", "HEAD")}
    2.times do
      output, error, status = Open3.capture3(environment, "bash", "-euo", "pipefail", "-c", tag, chdir: @root)
      assert status.success?, output + error
    end
    assert_equal "tag", git("cat-file", "-t", "refs/tags/v0.1.1")
    assert_equal git("rev-parse", "HEAD"), git("--git-dir", @origin, "rev-parse", "refs/tags/v0.1.1^{}")
    assert_empty git("ls-remote", "--tags", "origin", "refs/tags/local-backup")
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

  def test_preparation_rejects_dirty_stale_or_unmerged_starts
    output = command("bundle", "exec", "rake", "release:prepare[patch]", success: false)
    assert_includes output, "Start from main"
    git("switch", "main")
    File.write(File.join(@root, "unfinished"), "unfinished")
    assert_includes command("bundle", "exec", "rake", "release:prepare[patch]", success: false), "clean working tree"
    File.delete(File.join(@root, "unfinished"))
    git("switch", "feature/release")
    File.write(File.join(@root, "README.md"), "Unmerged\n")
    git("add", ".")
    git("commit", "-m", "feat: unmerged work")
    assert_includes command("bundle", "exec", "rake", "release:prepare[patch]", success: false), "origin/main"
    git("push", "--no-follow-tags", "origin", "HEAD:refs/heads/main")
    git("switch", "main")
    assert_includes command("bundle", "exec", "rake", "release:prepare[patch]", success: false), "origin/main"
    assert_empty git("status", "--porcelain")
    assert_equal "0.1.0", File.read(File.join(@root, "lib/fixture/version.rb"))[/VERSION = "([^"]+)"/, 1]
    git("merge", "--ff-only", "feature/release")
    git("switch", "-c", "chore/release-v0.1.1")
    File.write(File.join(@root, "README.md"), "Unmerged release work\n")
    git("add", "README.md")
    git("commit", "-m", "docs: preserve unmerged release work")
    unmerged = git("rev-parse", "HEAD")
    git("switch", "main")
    assert_includes command("bundle", "exec", "rake", "release:prepare[patch]", success: false), "contains unmerged commits"
    assert_equal unmerged, git("rev-parse", "chore/release-v0.1.1")
    assert_empty git("status", "--porcelain")
  end

  def test_initial_untagged_version_can_be_prepared_without_incrementing_it
    File.write(File.join(@root, "CHANGELOG.md"), "# Changelog\n")
    git("add", "CHANGELOG.md")
    git("commit", "-m", "docs: initialize changelog")
    git("switch", "main")
    git("merge", "--ff-only", "feature/release")
    git("push", "--no-follow-tags", "origin", "main", ":refs/tags/v0.1.0")
    git("tag", "-d", "v0.1.0")
    output = command("bundle", "exec", "rake", "release:prepare[0.1.0]")
    assert_includes output, "Merge this release PR"
    assert_equal "chore/release-v0.1.0", git("branch", "--show-current")
    assert_empty git("status", "--porcelain")
    assert_empty git("tag", "--list", "v0.1.0")
  end

  def test_failed_checks_leave_a_local_diff_without_pushing_or_opening_a_pr
    File.write(File.join(@root, "Rakefile"), "require \"rake\"\ntask(:test) { abort \"Fixture check failed\" }\nrequire \"ethos/gemkit/rake\"\n")
    git("add", "Rakefile")
    git("commit", "-m", "test: simulate a failed check")
    git("switch", "main")
    git("merge", "--ff-only", "feature/release")
    git("push", "--no-follow-tags", "origin", "main")
    before = git("rev-parse", "HEAD")
    output = command("bundle", "exec", "rake", "release:prepare[patch]", success: false)
    assert_includes output, "Fixture check failed"
    assert_equal before, git("rev-parse", "HEAD")
    assert_empty git("ls-remote", "--heads", "origin", "refs/heads/chore/release-v0.1.1")
    refute File.exist?(File.join(@directory, "pull-request"))
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
