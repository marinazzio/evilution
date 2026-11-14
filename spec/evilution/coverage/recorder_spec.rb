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

  context "unexecuted-line tracking at the end of the build" do
    let(:source) do
      snapshots(
        { target => [nil, 1, 0, 0, nil] }, # before: line 2 ran at load
        { target => [nil, 1, 1, 0, nil] }, # after: line 3 ran in the example
        { target => [nil, 1, 1, 0, nil] }  # the end of the build: line 4 never ran
      )
    end

    it "records the executable lines that never ran in the files the build vouches for" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target], vouched_files: [target], spec_files: ["/proj/spec/calc_spec.rb"])

      expect(map.uncovered?(target, [4])).to be(true)
      expect(map.uncovered?(target, [2])).to be(false)
      expect(map.uncovered?(target, [5])).to be(false) # not executable
      expect(map.to_h["missed_lines"]).to eq(target => [4])
      expect(map.built_from?(["/proj/spec/calc_spec.rb"])).to be(true)
    end

    it "records none for a file the build does not vouch for" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target], vouched_files: [])

      expect(map.uncovered?(target, [4])).to be(false)
    end
  end

  context "a line that first runs after the last example, as an after(:suite) hook can" do
    let(:source) do
      snapshots(
        { target => [nil, 0, 0] },
        { target => [nil, 1, 0] },
        { target => [nil, 1, 1] } # the end of the build: line 3 ran after the example
      )
    end

    it "counts it as executed" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target], vouched_files: [target])

      expect(map.executed?(target, 3)).to be(true)
      expect(map.uncovered?(target, [3])).to be(false)
    end
  end

  context "per-file counts in the { lines: [...] } shape, before and after the fork" do
    subject(:recorder) do
      described_class.new(target_files: [target], coverage_source: source,
                          prior_counts: { target => { lines: [1, 0, 0] } })
    end

    let(:source) { snapshots({ target => { lines: [0, 0, 0] } }) }

    it "reads the lines out of them" do
      map = recorder.to_map(built_files: [target], vouched_files: [target])

      expect(map.executed?(target, 1)).to be(true)
      expect(map.to_h["missed_lines"]).to eq(target => [1, 2, 3])
      expect(map.uncovered?(target, [2])).to be(true)
    end
  end

  context "a vouched file the coverage never saw" do
    let(:source) { snapshots({}, {}, {}) }

    it "records nothing for it" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target], vouched_files: [target])

      expect(map.uncovered?(target, [1])).to be(false)
    end
  end

  # A forked child starts its counts from zero, so what ran in the parent
  # before the fork (a preload loading the file) arrives as prior counts.
  context "counts from before the build's fork" do
    subject(:recorder) do
      described_class.new(target_files: [target], coverage_source: source,
                          prior_counts: { target => { lines: [1, 1, 0, 0, nil] } })
    end

    let(:source) do
      snapshots(
        { target => [0, 0, 0, 0, nil] },
        { target => [0, 0, 1, 0, nil] },
        { target => [0, 0, 1, 0, nil] }
      )
    end

    it "counts the lines that ran before the fork as executed, and never as unexecuted" do
      recorder.around_example("spec/calc_spec.rb:5") { :ran }
      map = recorder.to_map(built_files: [target], vouched_files: [target])

      expect(map.executed?(target, 1)).to be(true)
      expect(map.uncovered?(target, [2])).to be(false)
      expect(map.uncovered?(target, [3])).to be(false)
      expect(map.uncovered?(target, [4])).to be(true)
    end
  end
end
