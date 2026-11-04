# frozen_string_literal: true

require_relative "test_helper"
require "ethos/gemkit/branch"

class BranchTest < GemkitTest
  def test_git_branch_policy_blocks_protected_and_detached_commits
    in_fixture do |directory|
      git(directory, "init", "-b", "main")
      assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Branch.check(directory) }
      git(directory, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-m", "test: seed fixture")
      git(directory, "switch", "-c", "feature/example")
      assert Ethos::Gemkit::Branch.check(directory)
      git(directory, "switch", "-c", "master")
      assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Branch.check(directory) }
      git(directory, "checkout", "--detach")
      assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Branch.check(directory) }
    end
  end

  def test_non_repository_fails_clearly
    in_fixture do |directory|
      error = assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::Branch.check(directory) }
      assert_match "Cannot inspect Git branch", error.message
    end
  end

  private

  def git(directory, *arguments)
    output, error, status = Open3.capture3("git", *arguments, chdir: directory)
    assert status.success?, output + error
  end
end
