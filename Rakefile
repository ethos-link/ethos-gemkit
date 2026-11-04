require "bundler/setup"
require "rake/testtask"
require "bundler/gem_tasks"
require "ethos/gemkit/tasks"

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

task default: :verify
Rake::Task.tasks.select { |task| task.name == "release" || task.name.start_with?("release:") }.each do |task|
  task.clear
  task.enhance { abort "Publication is not enabled during toolkit bootstrap" }
end
