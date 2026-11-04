require "bundler/setup"
require "rake/testtask"
require "bundler/gem_tasks"
require "ethos/gemkit/tasks"

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

task default: :verify
Rake::Task[:release].clear
Rake::Task[:release].enhance { abort "Publication is not enabled during toolkit bootstrap" }
