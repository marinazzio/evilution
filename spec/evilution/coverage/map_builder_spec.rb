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

  it "records ABSOLUTE example locations so they replay regardless of CWD" do
    map = described_class.new(spec_files: [spec], target_files: [target]).call
    add_line = File.readlines(target).index { |l| l.include?("a + b") } + 1

    map.examples_for(target, add_line).each do |loc|
      expect(loc).to start_with("/") # absolute path, not RSpec's "./spec/..." form
    end
  end

  describe ".absolute_location" do
    it "expands a ./-relative location against the root, keeping the line suffix" do
      expect(described_class.absolute_location("./spec/a_spec.rb:5", "/proj"))
        .to eq("/proj/spec/a_spec.rb:5")
    end

    it "keeps a nested line suffix and an already-absolute path" do
      expect(described_class.absolute_location("/x/spec/a_spec.rb:5:9", "/proj"))
        .to eq("/x/spec/a_spec.rb:5:9")
    end
  end
end
