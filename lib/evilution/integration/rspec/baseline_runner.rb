# frozen_string_literal: true

require "stringio"
require_relative "../rspec"
require_relative "../../baseline"

class Evilution::Integration::RSpec::BaselineRunner
  def call(spec_file)
    require "rspec/core"
    # Anchor against PROJECT_ROOT under EV-wqxu sandbox CWD; see
    # FrameworkLoader#add_spec_load_path for rationale.
    spec_dir = File.expand_path("spec", Evilution.project_base_dir)
    $LOAD_PATH.unshift(spec_dir) unless $LOAD_PATH.include?(spec_dir)
    reset_examples
    output = StringIO.new
    status = ::RSpec::Core::Runner.run(
      ["--format", "progress", "--no-color", "--order", "defined", spec_file], output, output
    )
    report(status.zero?, output.string)
  end

  private

  # Examples are cleared, the configuration is kept: a helper loaded by
  # --preload is not loaded again by the spec's own require, so an
  # RSpec.configure block dropped here never comes back, and a spec relying on
  # it goes red in the baseline alone.
  def reset_examples
    ::RSpec.respond_to?(:clear_examples) ? ::RSpec.clear_examples : ::RSpec.reset
  end

  # What RSpec printed is the only account of a failure outside any example --
  # a file that does not load, a suite hook that raises.
  def report(passed, output)
    return Evilution::Baseline::Report.build(passed: true) if passed

    failures = failed_examples
    Evilution::Baseline::Report.build(passed: false, failures: failures, error: failures.empty? ? output : nil)
  end

  def failed_examples
    world = ::RSpec.world
    return [] unless world.respond_to?(:all_examples)

    world.all_examples
         .select { |example| example.execution_result.status == :failed }
         .map { |example| failure(example) }
  end

  def failure(example)
    exception = example.execution_result.exception
    {
      id: example.id,
      description: example.full_description,
      message: exception ? "#{exception.class}: #{exception.message}" : nil
    }
  end
end
