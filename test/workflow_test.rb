# frozen_string_literal: true

require_relative "test_helper"

class WorkflowTest < GemkitTest
  def workflow(name)
    YAML.safe_load_file(File.expand_path("../.github/workflows/#{name}.yml", __dir__))
  end

  def test_publishing_and_notes_have_no_consumer_checkout_or_bundle_install
    jobs = workflow("release").fetch("jobs")
    %w[publish notes].each do |name|
      steps = jobs.fetch(name).fetch("steps")
      refute steps.any? { |step| step.fetch("uses", "").start_with?("actions/checkout") }
      refute steps.any? { |step| step.fetch("run", "").include?("bundle") }
      assert steps.any? { |step| step["run"] == "sha256sum --check --strict SHA256SUMS" }
    end
    assert_equal ["build", "publish"], jobs.fetch("notes").fetch("needs")
    assert_equal "read", jobs.fetch("publish").fetch("permissions").fetch("contents")
    assert_equal "write", jobs.fetch("publish").fetch("permissions").fetch("packages")
    assert_equal "${{ secrets.PACKAGES_TOKEN || github.token }}", jobs.fetch("publish").fetch("steps").last.fetch("env").fetch("PACKAGES_TOKEN")
    assert_equal "write", jobs.fetch("notes").fetch("permissions").fetch("contents")
    setup = jobs.fetch("build").fetch("steps").find { |step| step["name"] == "Set up consumer verification dependencies" }
    assert_equal "${{ inputs.build-setup }}", setup.fetch("run")
    assert_equal "inputs.build-setup != ''", setup.fetch("if")
    assert_includes jobs.fetch("build").fetch("if"), "github.event_name == 'push'"
    assert_includes jobs.fetch("build").fetch("steps").first.fetch("with").fetch("ref"), "pull_request.merge_commit_sha"
    assert_includes jobs.fetch("build").fetch("if"), "pull_request.merged == true"
    assert_includes jobs.fetch("build").fetch("if"), "chore/release-v"
    assert_equal ["build", "tag"], jobs.fetch("publish").fetch("needs")
    assert_equal "write", jobs.fetch("tag").fetch("permissions").fetch("contents")
    assert jobs.fetch("tag").fetch("steps").none? { |step| step.fetch("run", "").include?("bundle") }
  end

  def test_private_publication_requires_a_token_and_uses_the_private_host
    in_fixture do |directory|
      script = workflow("release").fetch("jobs").fetch("publish").fetch("steps").last.fetch("run")
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      File.write(File.join(bin, "gem"), <<~SH)
        #!/bin/sh
        test "$GEM_HOST_API_KEY" = 'Bearer fixture-token' || exit 1
        test "$1" = push && test "$2" = fixture.gem && test "$3" = --host || exit 1
        test "$4" = https://rubygems.pkg.github.com/ethos-link || exit 1
        touch "$PUBLISHED"
      SH
      File.chmod(0o755, File.join(bin, "gem"))
      env = {"PATH" => "#{bin}:#{ENV.fetch("PATH")}", "GEM_HOST" => "https://rubygems.pkg.github.com/ethos-link",
             "GEM_FILE" => "fixture.gem", "PUBLISHED" => File.join(directory, "published"), "PACKAGES_TOKEN" => "", "GEM_HOST_API_KEY" => nil}
      refute Open3.capture3(env, "bash", "-euo", "pipefail", "-c", script).last.success?
      refute File.exist?(env.fetch("PUBLISHED"))
      env["PACKAGES_TOKEN"] = "fixture-token"
      assert Open3.capture3(env, "bash", "-euo", "pipefail", "-c", script).last.success?
      assert File.exist?(env.fetch("PUBLISHED"))
    end
  end

  def test_gitlab_validates_before_credentials_and_is_gated_by_a_url_and_main
    job = workflow("sync-gitlab").fetch("jobs").fetch("sync")
    assert_includes job.fetch("if"), "startsWith(inputs.url, 'git@')"
    assert_includes job.fetch("if"), "github.ref == 'refs/heads/main'"
    validation = job.fetch("steps").first
    refute validation.fetch("env").values.any? { |value| value.include?("secrets.") }
    [" ", "https://gitlab.example/group/repo.git", "git@gitlab.example:group/../repo.git"].each do |url|
      _, _, status = Open3.capture3({"GITLAB_URL" => url}, "bash", "-euo", "pipefail", "-c", validation.fetch("run"))
      refute status.success?
    end
  end

  def test_gitlab_sync_initializes_repeats_fetches_current_main_and_rejects_divergence
    in_fixture do |directory|
      repo, origin, target = %w[repo origin.git target.git].map { |name| File.join(directory, name) }
      FileUtils.mkdir_p(repo)
      git = ->(*args) {
        output, error, status = Open3.capture3("git", *args, chdir: repo)
        assert status.success?, output + error
        output.strip
      }
      git.call("init", "--bare", origin)
      git.call("init", "--bare", target)
      git.call("init", "-b", "feature/seed")
      git.call("config", "user.name", "Sync Test")
      git.call("config", "user.email", "sync@example.invalid")
      url = "git@gitlab.example:group/repo.git"
      git.call("config", "url.#{target}.insteadOf", url)
      File.write(File.join(repo, "README.md"), "first\n")
      git.call("add", ".")
      git.call("commit", "-m", "feat: seed fixture")
      git.call("branch", "main")
      git.call("tag", "-a", "local-backup", "-m", "Do not copy tags")
      git.call("config", "push.followTags", "true")
      git.call("remote", "add", "origin", origin)
      git.call("push", "--no-follow-tags", "origin", "main")
      script = workflow("sync-gitlab").fetch("jobs").fetch("sync").fetch("steps").last.fetch("run")
      env = {"GITLAB_URL" => url, "GITLAB_DEPLOY_KEY" => "fixture-key", "GITLAB_KNOWN_HOSTS" => "fixture-host",
             "GITHUB_STEP_SUMMARY" => File.join(directory, "summary")}
      sync = -> { Open3.capture3(env, "bash", "-euo", "pipefail", "-c", script, chdir: repo) }
      2.times {
        output, error, status = sync.call
        assert status.success?, output + error
      }
      assert_empty git.call("--git-dir", target, "tag", "--list")
      first = git.call("rev-parse", "HEAD")
      File.write(File.join(repo, "README.md"), "second\n")
      git.call("add", ".")
      git.call("commit", "-m", "feat: advance main")
      second = git.call("rev-parse", "HEAD")
      git.call("push", "--no-follow-tags", "origin", "HEAD:refs/heads/main")
      git.call("checkout", "--detach", first)
      output, error, status = sync.call
      assert status.success?, output + error
      assert_equal second, git.call("--git-dir", target, "rev-parse", "main")
      File.write(File.join(repo, "README.md"), "divergent\n")
      git.call("add", ".")
      git.call("commit", "-m", "feat: diverge target")
      git.call("--git-dir", target, "update-ref", "refs/heads/main", first)
      git.call("push", "--no-follow-tags", target, "HEAD:refs/heads/main")
      refute sync.call.last.success?
      assert_equal git.call("rev-parse", "HEAD"), git.call("--git-dir", target, "rev-parse", "main")
    end
  end
end
