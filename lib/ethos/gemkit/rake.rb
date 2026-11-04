# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

unless Rake::Task.task_defined?(:test)
  Rake::TestTask.new(:test) { |task|
    task.libs << "test"
    task.pattern = "test/**/*_test.rb"
  }
end
require_relative "release_tasks"
task default: :verify unless Rake::Task.task_defined?(:default)
