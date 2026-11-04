# frozen_string_literal: true

require_relative "test_helper"
require "ethos/gemkit/gitlab_sync"

class GitlabSyncTest < GemkitTest
  def test_missing_and_blank_urls_skip_without_accessing_git_or_credentials
    in_fixture do |root|
      [nil, "", "  \n"].each do |url|
        config = Ethos::Gemkit::Configuration.new(root, configuration.merge("gitlab_url" => url))
        repository = Object.new # Any accidental Git access fails this test.
        assert_match "skipped", Ethos::Gemkit::GitlabSync.new(config, repository: repository).run
      end
    end
  end

  def test_rejects_unsafe_urls_and_non_string_configuration
    in_fixture do |root|
      [false, true, [], "https://gitlab.com/group/repo", "git@gitlab.com:../repo.git", "git@gitlab.com:group/repo.git\ncommand", "git@host:group/repo.git"].each do |url|
        assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Configuration.new(root, configuration.merge("gitlab_url" => url)) }
      end
    end
  end

  def test_sync_initializes_main_repeats_fetches_current_main_and_rejects_divergence
    in_fixture do |root|
      target = File.join(root, "target.git")
      origin = File.join(root, "origin.git")
      repo = File.join(root, "repo")
      FileUtils.mkdir_p(repo)
      config = Ethos::Gemkit::Configuration.new(repo, configuration.merge("gitlab_url" => "git@gitlab.example:group/repo.git"))
      git = Ethos::Gemkit::Repository.new(config, origin: origin)
      git.git("init", "--bare", origin)
      git.git("init", "--bare", target)
      git.git("init", "-b", "feature/seed")
      git.git("config", "user.name", "Sync Test")
      git.git("config", "user.email", "sync@example.invalid")
      git.git("config", "url.#{target}.insteadOf", config.gitlab_url)
      File.write(File.join(repo, "README.md"), "first\n")
      git.git("add", ".")
      git.git("commit", "-m", "feat: seed sync")
      git.git("branch", "main")
      git.git("tag", "v1.0.0")
      git.git("remote", "add", "origin", origin)
      git.git("push", "origin", "main")
      sync = Ethos::Gemkit::GitlabSync.new(config, repository: git)
      assert_match "synchronized", sync.run
      assert_match "synchronized", sync.run
      assert_empty git.git("--git-dir", target, "tag", "--list")
      first = git.git("rev-parse", "HEAD")
      File.write(File.join(repo, "README.md"), "second\n")
      git.git("add", ".")
      git.git("commit", "-m", "feat: advance canonical main")
      git.git("push", "origin", "HEAD:refs/heads/main")
      second = git.git("rev-parse", "HEAD")
      git.git("checkout", "--detach", first) # Replayed stale event.
      sync.run
      assert_equal second, git.git("--git-dir", target, "rev-parse", "main")
      File.write(File.join(repo, "README.md"), "divergent\n")
      git.git("add", ".")
      git.git("commit", "-m", "feat: diverge target")
      divergent = git.git("rev-parse", "HEAD")
      git.git("--git-dir", target, "update-ref", "refs/heads/main", first)
      git.git("-c", "core.hooksPath=/dev/null", "push", target, "HEAD:refs/heads/main")
      assert_raises(Ethos::Gemkit::Error) { sync.run }
      assert_equal divergent, git.git("--git-dir", target, "rev-parse", "main")
    end
  end
end
