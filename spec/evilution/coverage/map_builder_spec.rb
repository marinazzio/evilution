# frozen_string_literal: true

require "spec_helper"
require "evilution/coverage/map_builder"

RSpec.describe Evilution::Coverage::MapBuilder do
  fixture_dir = File.expand_path("../../support/fixtures/coverage", __dir__)
  target = File.join(fixture_dir, "calculator.rb")
  # Named *_examples.rb (not *_spec.rb) so the host suite's default
  # spec/**/*_spec.rb pattern never auto-loads it: were calculator.rb required
  # in the parent before the build fork, the child's require would be a no-op
  # and ::Coverage would never instrument it.
  spec = File.join(fixture_dir, "calculator_examples.rb")

  # The builder runs a real RSpec process-in-process; guard wall time.
  it "maps each method's line to the example that exercises it" do
    map = described_class.new(spec_files: [spec], target_files: [target]).call

    add_line = File.readlines(target).index { |l| l.include?("a + b") } + 1
    sub_line = File.readlines(target).index { |l| l.include?("a - b") } + 1

    add_examples = map.examples_for(target, add_line)
    sub_examples = map.examples_for(target, sub_line)

    expect(add_examples).to include(a_string_matching(/calculator_examples\.rb:\d+/))
    expect(sub_examples).to include(a_string_matching(/calculator_examples\.rb:\d+/))
    # The "adds" example must not be credited with the subtraction line.
    expect(add_examples).not_to eq(sub_examples)
    expect(map.built?(target)).to be(true)
  end
end
