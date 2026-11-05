# frozen_string_literal: true

require_relative "tasks"
require_relative "release"

config = Ethos::Gemkit::Configuration.load
desc "Create a verified release PR from clean, up-to-date main"
task "release:prepare", [:target] do |_task, args|
  puts Ethos::Gemkit::Release.new(config).prepare(args[:target] || "patch")
end

desc "Verify release source and build using Bundler's native task"
task "release:build" do
  release = Ethos::Gemkit::Release.new(config)
  notes = release.verify(ENV.fetch("RELEASE_TAG"), tagged: ENV["RELEASE_FROM_PR"] != "true")
  Rake::Task[:build].invoke
  File.write(config.path("pkg/release-notes.md"), notes)
  Dir.chdir(config.path("pkg")) do
    sh "sha256sum", "#{release.spec.full_name}.gem", "release-notes.md", out: "SHA256SUMS"
  end
  if ENV["GITHUB_OUTPUT"]
    File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |file|
      file.puts "gem=#{release.spec.full_name}.gem", "host=#{release.spec.metadata.fetch("allowed_push_host")}", "tag=v#{release.spec.version}"
    end
  end
end

%w[release release:source_control_push release:rubygem_push].each do |name|
  Rake::Task[name].clear if Rake::Task.task_defined?(name)
  task(name) { abort "Publish a reviewed tag through GitHub Actions; local publication is disabled" }
end
