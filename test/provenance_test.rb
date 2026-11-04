# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require "ethos/gemkit/provenance"

class ProvenanceTest < GemkitTest
  def setup
    @commit, @tag_object = "a" * 40, "b" * 40
    @prefix = "repos/ethos-link/fixture"
    @responses = {
      "#{@prefix}/git/ref/tags/v0.1.1" => {"object" => {"type" => "tag", "sha" => @tag_object}},
      "#{@prefix}/git/tags/#{@tag_object}" => {"object" => {"type" => "commit", "sha" => @commit}},
      "#{@prefix}/actions/runs/123" => {"event" => "push", "head_sha" => @commit, "head_branch" => "v0.1.1", "path" => ".github/workflows/release.yml", "workflow_id" => 99},
      "#{@prefix}/actions/workflows/release.yml" => {"id" => 99},
      "#{@prefix}/actions/runs/123/jobs?per_page=100" => {"jobs" => [{"name" => "Build verified artifact / build", "conclusion" => "success"}]}
    }
    @record = {"repository" => "ethos-link/fixture", "tag" => "v0.1.1", "commit" => @commit, "tag_object" => @tag_object,
               "workflow_ref" => "ethos-link/fixture/.github/workflows/release.yml@refs/tags/v0.1.1"}
  end

  def check(record = @record)
    Ethos::Gemkit::Provenance.stub(:api, ->(path) { @responses.fetch(path) }) do
      Ethos::Gemkit::Provenance.verify(record, run_id: "123")
    end
  end

  def test_accepts_artifacts_only_from_the_successful_canonical_tag_build
    assert check
    %w[commit tag_object workflow_ref].each do |field|
      assert_raises(Ethos::Gemkit::Error) { check(@record.merge(field => "untrusted")) }
    end
  end

  def test_rejects_other_workflows_events_commits_and_unsuccessful_builds
    run = @responses.fetch("#{@prefix}/actions/runs/123")
    {"event" => "workflow_dispatch", "head_sha" => "c" * 40, "path" => ".github/workflows/other.yml", "workflow_id" => 98, "head_branch" => "main"}.each do |key, value|
      old = run[key]
      run[key] = value
      assert_raises(Ethos::Gemkit::Error) { check }
      run[key] = old
    end
    @responses.fetch("#{@prefix}/actions/runs/123/jobs?per_page=100")["jobs"].first["conclusion"] = "failure"
    assert_raises(Ethos::Gemkit::Error) { check }
  end

  def test_rejects_lightweight_canonical_tags
    @responses.fetch("#{@prefix}/git/ref/tags/v0.1.1").fetch("object")["type"] = "commit"
    assert_raises(Ethos::Gemkit::Error) { check }
  end
end
