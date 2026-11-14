# frozen_string_literal: true

require "evilution/integration/rspec"

RSpec.describe Evilution::Integration::RSpec::ExampleOrder do
  def example(scoped_id)
    double("Example #{scoped_id}", metadata: { rerun_file_path: "/p/a_spec.rb", scoped_id: scoped_id })
  end

  def group(*examples)
    double("Group", descendant_filtered_examples: examples)
  end

  def id(scoped_id)
    "/p/a_spec.rb[#{scoped_id}]"
  end

  let(:first) { example("1:1") }
  let(:second) { example("1:2") }
  let(:third) { example("1:3") }
  let(:fourth) { example("1:4") }

  describe "#order" do
    it "leaves the order alone outside a run" do
      order = described_class.new(durations: { id("1:1") => 2.0, id("1:2") => 1.0 })

      expect(order.order([first, second])).to eq([first, second])
    end

    it "runs the cheapest examples first" do
      order = described_class.new(durations: { id("1:1") => 2.0, id("1:2") => 0.5, id("1:3") => 1.0 })
      order.start([])

      expect(order.order([first, second, third])).to eq([second, third, first])
    end

    it "runs the examples that killed first, in the order given, before any cheaper one" do
      order = described_class.new(durations: { id("1:1") => 0.1, id("1:2") => 3.0, id("1:3") => 2.0 })
      order.start([id("1:3"), id("1:2")])

      expect(order.order([first, second, third])).to eq([third, second, first])
    end

    it "runs examples it has no time for after the timed ones" do
      order = described_class.new(durations: { id("1:2") => 5.0 })
      order.start([])

      expect(order.order([first, second])).to eq([second, first])
    end

    it "keeps the defined order between examples that compare equal" do
      order = described_class.new(durations: { id("1:1") => 1.0, id("1:2") => 1.0, id("1:3") => 1.0 })
      order.start([])

      expect(order.order([first, second, third])).to eq([first, second, third])
    end

    it "runs first the group that holds a killer" do
      order = described_class.new(durations: { id("1:1") => 0.1, id("1:2") => 0.1, id("1:3") => 4.0 })
      cheap = group(first, second)
      killing = group(third)
      order.start([id("1:3")])

      expect(order.order([cheap, killing])).to eq([killing, cheap])
    end

    it "runs the group whose examples take least time in all first, when none holds a killer" do
      order = described_class.new(durations: { id("1:1") => 0.5, id("1:2") => 0.5, id("1:3") => 0.6, id("1:4") => 2.0 })
      many_cheap = group(first, second)
      one_dear = group(fourth)
      one_cheap = group(third)
      order.start([])

      expect(order.order([one_dear, many_cheap, one_cheap])).to eq([one_cheap, many_cheap, one_dear])
    end

    it "keeps the defined order among many examples that compare equal" do
      examples = Array.new(40) { |i| example("1:#{i + 1}") }
      order = described_class.new(durations: examples.to_h { |e| [id(e.metadata[:scoped_id]), 1.0] })
      order.start([])

      expect(order.order(examples.reverse)).to eq(examples.reverse)
    end

    it "ranks a group by the best killer among its examples, wherever it sits in the group" do
      order = described_class.new(durations: {})
      late_killer = group(first, second)
      other_killer = group(third)
      order.start([id("1:2"), id("1:3")])

      expect(order.order([other_killer, late_killer])).to eq([late_killer, other_killer])
    end

    it "ranks a group by its best killer even when a lesser one comes first in it" do
      order = described_class.new(durations: {})
      mixed = group(third, first)
      single = group(second)
      order.start([id("1:1"), id("1:2"), id("1:3")])

      expect(order.order([single, mixed])).to eq([mixed, single])
    end

    it "orders a group with no examples left without failing" do
      order = described_class.new(durations: { id("1:1") => 1.0 })
      empty = group
      timed = group(first)
      order.start([])

      expect(order.order([timed, empty])).to eq([empty, timed])
    end

    it "forgets the killers of a run that was started again without finishing" do
      order = described_class.new(durations: { id("1:1") => 1.0, id("1:2") => 2.0 })
      order.start([id("1:2")])
      order.start([])

      expect(order.order([first, second])).to eq([first, second])
    end

    it "leaves the order alone again once the run is over" do
      order = described_class.new(durations: { id("1:1") => 2.0, id("1:2") => 1.0 })
      order.start([id("1:2")])
      order.finish

      expect(order.order([first, second])).to eq([first, second])
    end

    it "forgets the killers of the previous run" do
      order = described_class.new(durations: { id("1:1") => 1.0, id("1:2") => 2.0 })
      order.start([id("1:2")])
      order.finish
      order.start([])

      expect(order.order([first, second])).to eq([first, second])
    end
  end

  describe "#informed?" do
    it "is false with neither durations nor killers" do
      expect(described_class.new(durations: {}).informed?([])).to be(false)
    end

    it "is true with durations" do
      expect(described_class.new(durations: { id("1:1") => 1.0 }).informed?([])).to be(true)
    end

    it "is true with killers" do
      expect(described_class.new(durations: {}).informed?([id("1:1")])).to be(true)
    end
  end

  describe ".supported?" do
    it "is true for an RSpec that runs an ordering it is given by name" do
      expect(described_class.supported?).to be(true)
    end

    it "is false for an RSpec that ignores an ordering name it does not know" do
      hide_const("RSpec::Core::Ordering::Delayed")

      expect(described_class.supported?).to be(false)
    end
  end
end
