# frozen_string_literal: true

require_relative "../rspec"

# Names an example the same way wherever it runs.
#
# RSpec's own id starts with the spec file as it was given: `./spec/a_spec.rb`
# from the project root, an absolute path from an isolated worker that has
# changed directory. The baseline and a mutation run can therefore disagree
# about the same example, so the path is made absolute and symlinks are
# resolved before the position within the file is added.
module Evilution::Integration::RSpec::ExampleIds
  FAILED = :failed
  # An example with any of these statuses was run; one RSpec skipped, or never
  # reached because the run stopped, has no status at all.
  EXECUTED = %i[passed failed pending].freeze
  # A pending example's time says nothing about what running it costs.
  TIMED = %i[passed failed].freeze

  def self.of(example)
    metadata = example.metadata
    "#{canonical(metadata[:rerun_file_path])}[#{metadata[:scoped_id]}]"
  end

  # The ids of the examples that failed in the run RSpec.world still holds.
  def self.failed(world)
    return [] unless world.respond_to?(:all_examples)

    world.all_examples
         .select { |example| example.execution_result.status == FAILED }
         .map { |example| of(example) }
  end

  # How long each example that ran took, in seconds, by id.
  def self.durations(world)
    return {} unless world.respond_to?(:all_examples)

    world.all_examples.each_with_object({}) do |example, durations|
      result = example.execution_result
      durations[of(example)] = result.run_time if TIMED.include?(result.status)
    end
  end

  # How many examples the run in RSpec.world executed; nil when the world
  # cannot list them.
  def self.executed_count(world)
    return nil unless world.respond_to?(:all_examples)

    world.all_examples.count { |example| EXECUTED.include?(example.execution_result.status) }
  end

  def self.canonical(path)
    File.realpath(path)
  rescue SystemCallError
    File.expand_path(path)
  end
  private_class_method :canonical
end
