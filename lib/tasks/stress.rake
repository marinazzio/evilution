# frozen_string_literal: true

require "rspec/core/rake_task"

# RUN_STRESS lifts the default :stress exclusion in spec_helper. Set via a
# prerequisite so it runs before the RSpec task, without polluting other tasks.
task :stress_env do
  ENV["RUN_STRESS"] = "1"
end

desc "Run parallel/isolation stress + load specs (tagged :stress, slow)"
RSpec::Core::RakeTask.new(stress: :stress_env) do |t|
  t.pattern = "spec/evilution/parallel/stress_spec.rb"
  t.rspec_opts = "--tag stress"
end
