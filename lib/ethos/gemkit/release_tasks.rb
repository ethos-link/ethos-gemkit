# frozen_string_literal: true

require "rake"
require "tmpdir"
require_relative "release"
require_relative "artifact"

config = Ethos::Gemkit::Configuration.load
%w[release release:source_control_push release:rubygem_push].each do |name|
  Rake::Task[name].clear if Rake::Task.task_defined?(name)
  task name do
    abort "Use release:prepare[target] and release:tag. GitHub Actions publishes."
  end
end

desc "Verify all repository release gates without modifying metadata or publishing"
task "release:verify" => :verify

desc "Prepare and push verified release metadata from current main"
task "release:prepare", [:target] do |_task, args|
  puts Ethos::Gemkit::Release.new(config).prepare(args[:target])
end

desc "Resume the journaled release without rewriting existing tags"
task "release:resume" do
  puts Ethos::Gemkit::Release.new(config).resume
end

desc "Tag and push the verified metadata commit"
task "release:tag" do
  puts Ethos::Gemkit::Release.new(config).tag
end

desc "Validate a canonical annotated release tag"
task "release:verify_tag", [:tag] do |_task, args|
  puts Ethos::Gemkit::Release.new(config).verify_tag(args[:tag] || ENV.fetch("RELEASE_TAG"))
end

desc "Verify a tag and build the one release artifact with its digest and notes"
task "release:artifact", [:tag] do |_task, args|
  tag = args[:tag] || ENV.fetch("RELEASE_TAG")
  notes = Ethos::Gemkit::Release.new(config).verify_tag(tag)
  Rake::Task[:verify].invoke
  Ethos::Gemkit::Artifact.build(config, tag: tag, notes: notes)
end

desc "Run the complete release in disposable Git repositories and a local registry"
task "release:rehearse" do
  require_relative "rehearsal"
  puts Ethos::Gemkit::Rehearsal.new(config).run
end
