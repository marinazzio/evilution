# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

Dir.glob("lib/tasks/**/*.rake").each { |r| load r }

task default: %i[spec rubocop]
