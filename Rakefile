# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "spec"
  t.test_files = FileList["spec/**/*_test.rb"]
end

task default: :test
