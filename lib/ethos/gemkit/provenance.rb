# frozen_string_literal: true

require "open3"
require "json"
require_relative "configuration"

module Ethos
  module Gemkit
    class Provenance
      def self.api(path)
        output, _, status = Open3.capture3("gh", "api", path)
        raise Error, "Cannot establish GitHub release provenance" unless status.success?
        JSON.parse(output)
      rescue JSON::ParserError
        raise Error, "Invalid GitHub provenance response"
      end

      def self.context(repository:, tag:, run_id:)
        unless repository.match?(/\A[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.-]+\z/) && tag.match?(/\Av\d+\.\d+\.\d+\z/) && run_id.to_s.match?(/\A[1-9]\d*\z/)
          raise Error, "Invalid release provenance request"
        end
        prefix = "repos/#{repository}"
        object = api("#{prefix}/git/ref/tags/#{tag}").fetch("object")
        raise Error, "Canonical release tag must be annotated" unless object.fetch("type") == "tag"
        tag_object = object.fetch("sha")
        target = api("#{prefix}/git/tags/#{tag_object}").fetch("object")
        raise Error, "Annotated tag must identify a commit" unless target.fetch("type") == "commit"
        commit = target.fetch("sha")
        run = api("#{prefix}/actions/runs/#{run_id}")
        unless run["event"] == "push" && run["head_sha"] == commit && run["head_branch"] == tag && run["path"] == ".github/workflows/release.yml"
          raise Error, "Artifact run must be the canonical tag-push release workflow"
        end
        workflow = api("#{prefix}/actions/workflows/release.yml")
        raise Error, "Unexpected artifact workflow identity" unless run["workflow_id"] == workflow.fetch("id")
        jobs = api("#{prefix}/actions/runs/#{run_id}/jobs?per_page=100").fetch("jobs")
        unless jobs.any? { |job| job["name"].end_with?("/ build") && job["conclusion"] == "success" }
          raise Error, "The source run has no successful verified build job"
        end
        {"commit" => commit, "tag_object" => tag_object,
         "workflow_ref" => "#{repository}/.github/workflows/release.yml@refs/tags/#{tag}"}
      rescue KeyError
        raise Error, "Incomplete GitHub release provenance"
      end

      def self.verify(record, run_id:)
        expected = context(repository: record.fetch("repository"), tag: record.fetch("tag"), run_id: run_id)
        unless expected.all? { |key, value| record[key] == value }
          raise Error, "Artifact differs from canonical tag or workflow identity"
        end
        true
      end
    end
  end
end
