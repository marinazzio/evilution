# frozen_string_literal: true

require "evilution/integration/loading/callback_redeclaration"

RSpec.describe Evilution::Integration::Loading::CallbackRedeclaration do
  # The slice of ActiveSupport::Callbacks this module relies on: a chain per
  # name that can be read, cleared and appended to, re-declaration that drops
  # a same-symbol callback before appending, and `__update_callbacks` handing
  # each class of the hierarchy a copy of its chain. The real thing is
  # exercised by the callback subjects integration spec.
  # Compares by value, as a careless stand-in would: the module must still
  # tell two registrations apart.
  let(:callback_class) do
    Class.new do
      attr_reader :filter

      def initialize(filter, if_conditions = [])
        @filter = filter
        @if = if_conditions
        @unless = []
      end

      def ==(other) = other.is_a?(self.class) && filter == other.filter
      alias_method :eql?, :==

      def hash = filter.hash
    end
  end

  let(:chain_class) do
    Class.new do
      include Enumerable

      def initialize(callbacks = [])
        @callbacks = callbacks
      end

      def each(&) = @callbacks.each(&)
      def clear = @callbacks.clear
      def initialize_copy(other) = @callbacks = other.to_a.dup

      def append(callback)
        @callbacks.reject! { |existing| callback.filter.is_a?(Symbol) && existing.filter == callback.filter }
        @callbacks << callback
      end
    end
  end

  let(:model) do
    chains = chain_class
    Class.new do
      define_singleton_method(:__callbacks) { @__callbacks ||= superclass.__callbacks.transform_values(&:dup) }
      define_singleton_method(:set_callbacks) { |name, chain| __callbacks[name] = chain }
      define_singleton_method(:__update_callbacks) do |name, &block|
        [self, *subclasses].each { |target| block.call(target, target.__callbacks[name].dup) }
      end
      define_singleton_method(:declare) do |callback|
        __update_callbacks(:save) do |target, chain|
          chain.append(callback)
          target.set_callbacks(:save, chain)
        end
      end
      singleton_class.send(:define_method, :inherited, &:__callbacks)
      @__callbacks = { save: chains.new, validate: chains.new }
    end
  end

  let(:file) { __FILE__ }

  def filters(klass, name = :save)
    klass.__callbacks[name].map(&:filter)
  end

  def redeclare(klass, lines, &)
    described_class.call(klass, file, lines, &)
  end

  it "runs the declaration and returns its value for a class without callbacks" do
    plain = Class.new

    expect(described_class.call(plain, file, 1..1) { :declared }).to eq(:declared)
  end

  it "returns the declaration's value" do
    expect(redeclare(model, 1..1) { :declared }).to eq(:declared)
  end

  it "leaves the chains alone when the declaration registers nothing" do
    model.declare(callback_class.new(:first))

    redeclare(model, 1..1) { nil }

    expect(filters(model)).to eq([:first])
  end

  it "puts a re-declared symbol callback back where it was" do
    model.declare(callback_class.new(:first))
    model.declare(callback_class.new(:second))
    model.declare(callback_class.new(:third))
    fresh = callback_class.new(:second)

    redeclare(model, 1..1) { model.declare(fresh) }

    expect(filters(model)).to eq(%i[first second third])
    expect(model.__callbacks[:save].to_a[1]).to equal(fresh)
  end

  it "replaces a block callback written on the declaration's lines instead of adding a second" do
    original = proc { :original }
    line = __LINE__ - 1
    replacement = proc { :replacement }
    model.declare(callback_class.new(:first))
    model.declare(callback_class.new(original))
    model.declare(callback_class.new(:last))

    redeclare(model, line..line) { model.declare(callback_class.new(replacement)) }

    expect(filters(model)).to eq([:first, replacement, :last])
  end

  it "recognises the old callback by the place its condition was written" do
    condition = proc { true }
    line = __LINE__ - 1
    validator = Object.new
    fresh_validator = Object.new
    model.declare(callback_class.new(validator, [condition]))
    model.declare(callback_class.new(:last))

    redeclare(model, line..line) { model.declare(callback_class.new(fresh_validator, [proc { false }])) }

    expect(filters(model)).to eq([fresh_validator, :last])
  end

  it "leaves a block callback written elsewhere in the file alone" do
    other = proc { :other }
    line = __LINE__ - 1
    model.declare(callback_class.new(other))
    fresh = proc { :fresh }

    redeclare(model, (line + 50)..(line + 50)) { model.declare(callback_class.new(fresh)) }

    expect(filters(model)).to eq([other, fresh])
  end

  it "leaves a block callback written on the same line of another file alone" do
    other = proc { :other }
    line = __LINE__ - 1
    model.declare(callback_class.new(other))
    fresh = proc { :fresh }

    described_class.call(model, "/somewhere/else.rb", line..line) { model.declare(callback_class.new(fresh)) }

    expect(filters(model)).to eq([other, fresh])
  end

  # The source this is called from has other class-body calls blanked, so a
  # proc created there reports a line of its own, not the declaration's.
  it "replaces what it registered last time, wherever those procs say they were written" do
    original = proc { :original }
    line = __LINE__ - 1
    model.declare(callback_class.new(:first))
    model.declare(callback_class.new(original))
    model.declare(callback_class.new(:last))
    mutated = eval("proc { :mutated }", binding, __FILE__, line + 500) # rubocop:disable Style/EvalWithLocation
    restored = proc { :restored }

    redeclare(model, line..line) { model.declare(callback_class.new(mutated)) }
    redeclare(model, line..line) { model.declare(callback_class.new(restored)) }

    expect(filters(model)).to eq([:first, restored, :last])
  end

  it "does not take what another declaration registered for its own, though it reports this one's lines" do
    mine = proc { :mine }
    my_line = __LINE__ - 1
    theirs = proc { :theirs }
    their_line = __LINE__ - 1
    model.declare(callback_class.new(mine))
    model.declare(callback_class.new(theirs))
    their_mutant = eval("proc { :their_mutant }", binding, __FILE__, my_line)
    my_mutant = proc { :my_mutant }

    redeclare(model, their_line..their_line) { model.declare(callback_class.new(their_mutant)) }
    redeclare(model, my_line..my_line) { model.declare(callback_class.new(my_mutant)) }

    expect(filters(model)).to eq([my_mutant, their_mutant])
  end

  it "appends when there is nothing to replace" do
    model.declare(callback_class.new(:first))

    redeclare(model, 1..1) { model.declare(callback_class.new(:added)) }

    expect(filters(model)).to eq(%i[first added])
  end

  it "puts several new callbacks in the place of the old ones, in order" do
    one = proc { 1 }
    two = proc { 2 }
    line = __LINE__ - 2
    model.declare(callback_class.new(:first))
    model.declare(callback_class.new(one))
    model.declare(callback_class.new(:middle))
    model.declare(callback_class.new(two))
    fresh = [proc { 3 }, proc { 4 }]

    redeclare(model, line..(line + 1)) { fresh.each { |callable| model.declare(callback_class.new(callable)) } }

    expect(filters(model)).to eq([:first, *fresh, :middle])
  end

  it "rebuilds a subclass's chain too, keeping the callbacks it added itself" do
    model.declare(callback_class.new(:first))
    model.declare(callback_class.new(:second))
    child = Class.new(model)
    child.declare(callback_class.new(:own))

    redeclare(model, 1..1) { model.declare(callback_class.new(:first)) }

    expect(filters(model)).to eq(%i[first second])
    expect(filters(child)).to eq(%i[first second own])
  end

  it "leaves chains the declaration did not touch as they were" do
    untouched = model.__callbacks[:validate]

    redeclare(model, 1..1) { model.declare(callback_class.new(:first)) }

    expect(model.__callbacks[:validate]).to equal(untouched)
  end

  describe "validator reflection" do
    let(:old_validator) { Object.new }
    let(:new_validator) { Object.new }
    let(:condition) { proc { true } }
    let(:line) { condition.source_location.last }

    before do
      model.define_singleton_method(:_validators) { @_validators ||= Hash.new { |hash, key| hash[key] = [] } }
      model.declare(callback_class.new(old_validator, [condition]))
      model._validators[:title] << old_validator
    end

    def redeclare_validator
      redeclare(model, line..line) do
        model._validators[:title] << new_validator
        model.declare(callback_class.new(new_validator, [proc { false }]))
      end
    end

    it "exchanges the old validator for the new one" do
      redeclare_validator

      expect(model._validators[:title]).to eq([new_validator])
    end

    it "exchanges it in a subclass's own list as well" do
      child = Class.new(model)
      child.define_singleton_method(:_validators) { @_validators ||= { title: superclass._validators[:title].dup } }
      child._validators

      redeclare_validator

      expect(child._validators[:title]).to eq([new_validator])
    end

    it "leaves other validators where they were" do
      other = Object.new
      model._validators[:title].unshift(other)
      model._validators[:body] << other

      redeclare_validator

      expect(model._validators).to eq(title: [other, new_validator], body: [other])
    end
  end
end
