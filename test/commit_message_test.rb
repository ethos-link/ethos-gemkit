# frozen_string_literal: true

require_relative "test_helper"
require "ethos/gemkit/commit_message"

class CommitMessageTest < GemkitTest
  def test_accepts_the_shared_types_including_ci_and_build
    Ethos::Gemkit::CommitMessage::TYPES.each do |type|
      message = "#{type}(tooling): centralize verification\n\nKeep local and CI checks consistent.\n"
      original = message.dup
      assert Ethos::Gemkit::CommitMessage.validate(message)
      assert_equal original, message
    end
  end

  def test_rejects_unsupported_types_and_invalid_headers
    ["feature: add a thing", "style: format files", "fix: ", "fix(api) add a thing", "not a commit\n\nfeat: hidden header", "feat: add a check\nBody without a separator"].each do |message|
      assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::CommitMessage.validate(message) }
    end
  end

  def test_subject_limit_applies_to_the_original_ci_header
    assert Ethos::Gemkit::CommitMessage.validate("ci: " + "x" * 68)
    assert_raises(Ethos::Gemkit::Error) { Ethos::Gemkit::CommitMessage.validate("ci: " + "x" * 69) }
  end

  def test_preserves_inline_references_and_ignores_git_template_comments
    message = "fix(api)!: handle issue #123\n\nExplain the boundary.\n\n# Git template comment\n"
    assert Ethos::Gemkit::CommitMessage.validate(message)
    assert_includes message, "#123"
  end
end
