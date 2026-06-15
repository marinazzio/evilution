# frozen_string_literal: true

require "spec_helper"
require "evilution/coverage/recorder"

RSpec.describe Evilution::Coverage::Recorder do
  # Synthetic coverage snapshots: the recorder reads whatever coverage_source
  # returns. Each element is line-execution counts (line 1 at index 0).
  def snapshots(*frames)
    queue = frames.dup
    -> { queue.shift }
  end

  let(:target) { "/proj/lib/calc.rb" }

  subject(:recorder) do
    described_class.new(target_files: [target], coverage_source: source)
  end

  context "a single example that newly executes lines 2 and 3" do
    let(:source) do
      snapshots(
        { target => [nil, 0, 0, 0] }, # before
        { target => [nil, 0, 1, 1] }  # after: lines 3 and 4 ran (index 2,3)
      )
    end

    it "attributes the newly-covered lines to that example" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target])
      expect(map.examples_for(target, 3)).to eq(["spec/calc_spec.rb:5"])
      expect(map.examples_for(target, 4)).to eq(["spec/calc_spec.rb:5"])
    end

    it "does not attribute lines that did not increase" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target])
      expect(map.examples_for(target, 2)).to eq([]) # stayed 0
    end

    it "returns the block's value" do
      expect(recorder.around_example("spec/calc_spec.rb:5") { :sentinel }).to eq(:sentinel)
    end
  end

  context "lines outside the target file set" do
    let(:other) { "/proj/lib/other.rb" }
    let(:source) do
      snapshots(
        { target => [nil, 0], other => [nil, 0] },
        { target => [nil, 0], other => [nil, 5] } # only `other` advanced
      )
    end

    it "ignores coverage in non-target files" do
      recorder.around_example("spec/x_spec.rb:1") { :ran }
      map = recorder.to_map(built_files: [target])
      expect(map.examples_for(other, 2)).to eq([])
    end
  end

  context "modern Coverage.peek_result shape ({ path => { lines: [...] } })" do
    # Ruby's Coverage.start(lines: true) yields per-file { lines: [...] } hashes,
    # not bare count arrays. The recorder must read the :lines array out of them.
    let(:source) do
      snapshots(
        { target => { lines: [nil, 0, 0] } },
        { target => { lines: [nil, 0, 1] } } # line 3 (index 2) newly ran
      )
    end

    it "attributes lines from the :lines array of the per-file hash" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target])
      expect(map.examples_for(target, 3)).to eq(["spec/calc_spec.rb:5"])
      expect(map.examples_for(target, 2)).to eq([])
    end
  end

  context "executed-line tracking (a line covered at load, attributed to no example)" do
    let(:source) do
      snapshots(
        { target => [nil, 1, 0] }, # before: line 2 already ran (loaded), line 3 not
        { target => [nil, 1, 1] }  # after: line 3 newly ran; line 2 unchanged at 1
      )
    end

    it "marks every covered line executed, but only attributes the lines that increased" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target])

      expect(map.examples_for(target, 2)).to eq([]) # not attributed -- no increase
      expect(map.examples_for(target, 3)).to eq(["spec/calc_spec.rb:5"])
      expect(map.executed?(target, 2)).to be(true)  # load-covered -> executed, not a gap
      expect(map.executed?(target, 3)).to be(true)
    end
  end

  context "two examples touching overlapping lines" do
    let(:source) do
      snapshots(
        { target => [nil, 0, 0] }, { target => [nil, 1, 0] }, # ex A -> line 2
        { target => [nil, 1, 0] }, { target => [nil, 2, 1] }  # ex B -> lines 2,3
      )
    end

    it "records each example that advanced a line" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      recorder.around_example("spec/calc_spec.rb:9") { :ran }
      map = recorder.to_map(built_files: [target])
      expect(map.examples_for(target, 2)).to eq(["spec/calc_spec.rb:5", "spec/calc_spec.rb:9"])
      expect(map.examples_for(target, 3)).to eq(["spec/calc_spec.rb:9"])
    end
  end
end
