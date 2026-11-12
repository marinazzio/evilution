# frozen_string_literal: true

require "evilution/integration/loading/callback_equivalence"

RSpec.describe Evilution::Integration::Loading::CallbackEquivalence do
  # The parts of an ActiveSupport callback the comparison reads.
  let(:callback_class) do
    Class.new do
      attr_reader :kind

      def initialize(filter, if_conditions: [], unless_conditions: [], kind: :before)
        @filter = filter
        @if = if_conditions
        @unless = unless_conditions
        @kind = kind
      end
    end
  end

  let(:validator_class) do
    Class.new do
      def initialize(*attributes, **options)
        @attributes = attributes
        @options = options
      end
    end
  end

  def callback(filter, **)
    callback_class.new(filter, **)
  end

  def same?(one, other)
    described_class.call(one, other)
  end

  it "holds two callbacks naming the same method, under the same conditions, the same" do
    expect(same?(callback(:normalize, if_conditions: [:paid?]), callback(:normalize, if_conditions: [:paid?])))
      .to be(true)
  end

  it "tells callbacks apart by their filter, either condition, or kind" do
    original = callback(:normalize, if_conditions: [:paid?], unless_conditions: [:draft?])

    expect(
      [
        callback(:other, if_conditions: [:paid?], unless_conditions: [:draft?]),
        callback(:normalize, if_conditions: [:due?], unless_conditions: [:draft?]),
        callback(:normalize, if_conditions: [:paid?], unless_conditions: [:void?]),
        callback(:normalize, if_conditions: [:paid?], unless_conditions: [:draft?], kind: :after)
      ].map { |other| same?(original, other) }
    ).to eq([false, false, false, false])
  end

  it "compares callbacks that have no kind by what they hold" do
    plain = Class.new { def initialize(filter) = @filter = filter }

    expect([same?(plain.new(:a), plain.new(:a)), same?(plain.new(:a), plain.new(:b))]).to eq([true, false])
  end

  it "holds two validators of a class with the same attributes and options the same" do
    one = validator_class.new(:for_lift, in: [true], if: :lift_round?)
    other = validator_class.new(:for_lift, in: [true], if: :lift_round?)

    expect(same?(callback(one), callback(other))).to be(true)
  end

  it "tells validators apart by any value they hold, or by their class" do
    original = validator_class.new(:for_lift, in: [true])
    subclass = Class.new(validator_class)

    expect(
      [
        validator_class.new(:for_lift, in: [false]),
        validator_class.new(:for_lift, in: [true, false]),
        validator_class.new(:for_lift, within: [true]),
        validator_class.new(:title, in: [true]),
        subclass.new(:for_lift, in: [true])
      ].map { |other| same?(callback(original), callback(other)) }
    ).to eq([false, false, false, false, false])
  end

  it "holds equal plain values the same, whatever objects they are" do
    values = [+"text", 1, 1.5, 1..2, /a/, true, false, nil]

    expect(values.map { |value| same?(callback(value), callback(value.dup)) }).to all(be(true))
  end

  it "tells different plain values apart" do
    pairs = [%w[text other], [1, 2], [1.5, 2.5], [1..2, 1..3], [/a/, /b/], %i[a b], [true, false], [nil, false]]

    expect(pairs.map { |one, other| same?(callback(one), callback(other)) }).to all(be(false))
  end

  # A Struct, Data, Time or Set keeps what it holds out of instance
  # variables, and says itself whether another is equal.
  it "compares values that hold nothing in instance variables by their own equality" do
    pair = Struct.new(:a)
    point = Data.define(:a)
    values = [[pair.new(1), pair.new(1), pair.new(2)], [point.new(1), point.new(1), point.new(2)],
              [Time.at(1), Time.at(1), Time.at(2)], [Set[:a], Set[:a], Set[:b]]]

    expect(values.map { |one, equal, other| [same?(callback(one), callback(equal)), same?(callback(one), callback(other))] })
      .to all(eq([true, false]))
  end

  it "compares an object holding instance variables by them, though it says what it equals" do
    lenient = Class.new do
      def initialize(value) = @value = value
      def ==(_other) = true
    end

    expect(same?(callback(lenient.new(1)), callback(lenient.new(2)))).to be(false)
  end

  it "compares the values of hashes as their own, holding procs written in the same place the same" do
    procs = Array.new(2) { proc { :same } }

    expect(same?(callback({ if: procs.first }), callback({ if: procs.last }))).to be(true)
  end

  it "tells a number from an equal one of another class" do
    expect(same?(callback(1), callback(1.0))).to be(false)
  end

  it "holds two objects of a class that holds nothing and compares by identity the same" do
    stateless = Class.new

    expect(same?(callback(stateless.new), callback(stateless.new))).to be(true)
  end

  it "tells apart objects holding the same values under other names" do
    one = validator_class.new
    one.instance_variable_set(:@extra, 1)
    other = validator_class.new
    other.instance_variable_set(:@more, 1)

    expect(same?(callback(one), callback(other))).to be(false)
  end

  it "holds a proc that cannot say where it was written the same as itself only" do
    native = method(:puts).to_proc

    expect([same?(callback(native), callback(native)), same?(callback(native), callback(method(:puts).to_proc))])
      .to eq([true, false])
  end

  it "holds procs written in the same place the same, and no others" do
    procs = Array.new(2) { proc { :same } }
    elsewhere = proc { :same }

    expect([same?(callback(procs.first), callback(procs.last)), same?(callback(procs.first), callback(elsewhere))])
      .to eq([true, false])
  end

  it "holds a class the same as itself only" do
    one = Class.new { @table = :orders }
    lookalike = Class.new { @table = :orders }

    expect([same?(callback(one), callback(one)), same?(callback(one), callback(lookalike))]).to eq([true, false])
  end

  it "compares nested values down to a fixed depth, and by identity below it" do
    nest = ->(levels) { levels.zero? ? [:leaf] : [nest.call(levels - 1)] }

    expect([same?(callback(nest.call(8)), callback(nest.call(8))), same?(callback(nest.call(9)), callback(nest.call(9)))])
      .to eq([true, false])
  end

  it "ends on values that hold themselves, telling them apart" do
    one = validator_class.new
    one.instance_variable_set(:@self, one)
    other = validator_class.new
    other.instance_variable_set(:@self, other)

    expect([same?(callback(one), callback(other)), same?(callback(one), callback(one))]).to eq([false, true])
  end
end
