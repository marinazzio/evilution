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

  def redeclare(klass, lines, original = nil, &)
    described_class.call(klass, file, lines, original, &)
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

  # The neighbours are objects: the stand-in chain drops a repeated symbol.
  it "puts what a declaration registers back where it was, after a run that registered nothing" do
    original = proc { :original }
    line = __LINE__ - 1
    first = Object.new
    last = Object.new
    model.declare(callback_class.new(first))
    model.declare(callback_class.new(original))
    model.declare(callback_class.new(last))
    restored = proc { :restored }
    redeclare(model, line..line) { nil }

    redeclare(model, line..line) { model.declare(callback_class.new(restored)) }

    expect(filters(model)).to eq([first, restored, last])
  end

  it "puts it back where the first of what it registered was, when that was apart" do
    one = proc { 1 }
    two = proc { 2 }
    line = __LINE__ - 2
    middle = Object.new
    last = Object.new
    [one, middle, two, last].each { |filter| model.declare(callback_class.new(filter)) }
    restored = proc { :restored }
    redeclare(model, line..(line + 1)) { nil }

    redeclare(model, line..(line + 1)) { model.declare(callback_class.new(restored)) }

    expect(filters(model)).to eq([restored, middle, last])
  end

  it "keeps the place one declaration left for itself alone" do
    original = proc { :original }
    line = __LINE__ - 1
    model.declare(callback_class.new(original))
    model.declare(callback_class.new(:last))
    redeclare(model, line..line) { nil }
    added = proc { :added }

    redeclare(model, 900..900) { model.declare(callback_class.new(added)) }

    expect(filters(model)).to eq([:last, added])
  end

  it "replaces what it appended last time, though its procs say they were written elsewhere" do
    appended = eval("proc { :appended }", binding, __FILE__, 1) # rubocop:disable Style/EvalWithLocation
    replacement = proc { :replacement }
    model.declare(callback_class.new(:first))
    redeclare(model, 900..900) { model.declare(callback_class.new(appended)) }

    redeclare(model, 900..900) { model.declare(callback_class.new(replacement)) }

    expect(filters(model)).to eq([:first, replacement])
  end

  # `validates :for_lift, inclusion: { in: [true] }, if: :lift_round?`
  # registers a validator object under a symbol condition: nothing in it says
  # where it was written. Given the declaration as it is written in the file,
  # the module runs that again first, and what it registers now is what it
  # registered then, value for value.
  describe "given the original declaration" do
    let(:validator_class) do
      Class.new do
        attr_reader :attributes, :options

        def initialize(*attributes, **options)
          @attributes = attributes
          @options = options
        end
      end
    end

    let(:original) { validator_class.new(:for_lift, in: [true]) }
    let(:fresh) { validator_class.new(:for_lift, in: [true, false]) }

    before do
      callbacks = callback_class
      validators = validator_class
      model.define_singleton_method(:declare_original) do
        declare(callbacks.new(validators.new(:for_lift, in: [true]), [:lift_round?]))
      end
      model.declare(callback_class.new(:first))
      model.declare(callback_class.new(original, [:lift_round?]))
      model.declare(callback_class.new(:last))
    end

    it "puts the mutated declaration's validator where the original's was" do
      redeclare(model, 1..1, "declare_original") { model.declare(callback_class.new(fresh, [:lift_round?])) }

      expect(filters(model)).to eq([:first, fresh, :last])
    end

    it "drops the original's validator when the mutated declaration registers none" do
      redeclare(model, 1..1, "declare_original") { nil }

      expect(filters(model)).to eq(%i[first last])
    end

    it "leaves a validator that differs from the original's in any value alone" do
      lookalike = validator_class.new(:for_lift, in: [false])
      model.declare(callback_class.new(lookalike, [:lift_round?]))

      redeclare(model, 1..1, "declare_original") { model.declare(callback_class.new(fresh, [:lift_round?])) }

      expect(filters(model)).to eq([:first, fresh, :last, lookalike])
    end

    it "puts what it registers again where the original's was, after a run that registered none" do
      restored = validator_class.new(:for_lift, in: [true])
      redeclare(model, 1..1, "declare_original") { nil }

      redeclare(model, 1..1, "declare_original") { model.declare(callback_class.new(restored, [:lift_round?])) }

      expect(filters(model)).to eq([:first, restored, :last])
    end

    it "replaces each of several validators the original registers" do
      second = validator_class.new(:title)
      callbacks = callback_class
      validators = validator_class
      model.declare(callback_class.new(second))
      model.define_singleton_method(:declare_both) do
        declare_original
        declare(callbacks.new(validators.new(:title)))
      end
      fresh_second = validator_class.new(:title, in: [1])

      redeclare(model, 1..1, "declare_both") do
        model.declare(callback_class.new(fresh, [:lift_round?]))
        model.declare(callback_class.new(fresh_second))
      end

      expect(filters(model)).to eq([:first, fresh, fresh_second, :last])
    end

    it "settles a later run against the original after one that changed nothing" do
      redeclare(model, 1..1) { nil }

      redeclare(model, 1..1, "declare_original") { model.declare(callback_class.new(fresh, [:lift_round?])) }

      expect(filters(model)).to eq([:first, fresh, :last])
    end

    it "does not run the original again after a run that registered nothing" do
      runs = 0
      model.define_singleton_method(:count_original) { runs += 1 }
      condition = proc { true }
      line = __LINE__ - 1
      model.declare(callback_class.new(validator_class.new(:title), [condition]))
      redeclare(model, line..line) { nil }

      redeclare(model, line..line, "count_original") { nil }

      expect(runs).to eq(0)
    end

    it "runs the original again for a declaration on the same line of another file" do
      runs = 0
      model.define_singleton_method(:count_original) { runs += 1 }
      redeclare(model, 1..1, "count_original; declare_original") { nil }

      described_class.call(model, "/somewhere/else.rb", 1..1, "count_original") { nil }

      expect(runs).to eq(2)
    end

    it "lets an interrupt of the original through" do
      expect { redeclare(model, 1..1, "raise Interrupt") { nil } }.to raise_error(Interrupt)
    end

    it "runs the original the first time only" do
      runs = 0
      model.define_singleton_method(:count_original) { runs += 1 }

      2.times { redeclare(model, 1..1, "count_original; declare_original") { nil } }

      expect(runs).to eq(1)
    end

    it "does without it when it cannot be run on its own" do
      redeclare(model, 1..1, "local_only_in_the_class_body") { model.declare(callback_class.new(fresh)) }

      expect(filters(model)).to eq([:first, original, :last, fresh])
    end
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

    it "drops the old validator when the declaration registers none in its place" do
      redeclare(model, line..line) { nil }

      expect([filters(model), model._validators[:title]]).to eq([[], []])
    end

    it "lists the next one in a subclass's own list again, after a run that registered none" do
      child = Class.new(model)
      child.define_singleton_method(:_validators) { @_validators ||= { title: superclass._validators[:title].dup } }
      child._validators
      redeclare(model, line..line) { nil }

      redeclare_validator

      expect([model._validators[:title], child._validators[:title]]).to eq([[new_validator], [new_validator]])
    end

    it "lists a new validator only for the attributes the class lists it for, in a subclass" do
      child = Class.new(model)
      child.define_singleton_method(:_validators) do
        @_validators ||= { title: superclass._validators[:title].dup, body: [] }
      end
      child._validators
      redeclare(model, line..line) { nil }

      redeclare_validator

      expect(child._validators).to eq(title: [new_validator], body: [])
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
