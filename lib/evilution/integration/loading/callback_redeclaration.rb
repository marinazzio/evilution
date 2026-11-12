# frozen_string_literal: true

require_relative "../loading"
require_relative "callback_equivalence"
require_relative "../../diagnostic"

# Runs a callback declaration again and puts what it registers where the
# callbacks it registered before were.
#
# ActiveSupport::Callbacks does not replace on re-declaration. A callback
# named by a symbol is dropped and added again at the end of its chain; one
# that is a block or an object (a validator) is simply added, next to the
# first. Either way a mutated `if:` would run in a chain that is no longer
# the one the class was written with -- reordered, or with the unmutated
# original still answering.
#
# So the chains are read before the declaration runs and rebuilt afterwards:
# the callbacks this declaration registered last time give their place to the
# new ones, and everything else stays where it was, including what subclasses
# added themselves. See BodyCallNeutralizer for the source that calls this.
#
# "Last time" is the file's own load the first time round. Those callbacks
# are recognised by where their procs were written, or by having been dropped
# as duplicates. A validator under a symbol condition, or none -- `validates
# :for_lift, inclusion: { in: [true] }` -- has no proc to go by, and the
# mutated declaration registers it with other values. So when the module is
# given the declaration as it is written in the file, it runs that again
# first, in the class body it is written in, so that it reads the constants
# and local variables the body sees: what it registers then is the same,
# value for value, as what it registered on load, and takes its place -- one
# callback for each it registers, and none the class inherited. After that
# the module goes by what
# it registered itself: a mutation can add or remove lines, so a proc created
# by the mutated source may report a line that belongs to another declaration
# of the real file.
#
# A declaration that now registers nothing -- `inclusion: nil`, `presence:
# false` -- leaves nothing in the place of what it registered before, and
# what it registers on a later run goes back to that place.
module Evilution::Integration::Loading::CallbackRedeclaration
  CONDITIONS = %i[@if @unless].freeze
  private_constant :CONDITIONS

  # klass: the class whose body the declaration is written in. file, lines:
  # where the declaration is in the file as it was loaded. original: the
  # declaration's source as written there, or nil. body: the binding of the
  # class body it is written in, or nil to run it in the class alone.
  def self.call(klass, file, lines, original = nil, body = nil, &)
    return yield unless klass.respond_to?(:__callbacks)

    origin = Origin.new(file, lines)
    rerun_original(klass, origin, Original.new(original, body)) if original && !ledger.registered.key?(key(klass, origin))
    redeclare(klass, origin, &)
  end

  # rerun: whether the declaration runs as written in the file, registering
  # what it did on load once more.
  def self.redeclare(klass, origin, rerun: false)
    before = klass.__callbacks.transform_values(&:to_a)
    result = yield
    swaps = Settlement.new(klass, origin, ledger, key(klass, origin), rerun: rerun).call(before)
    swap_validators(klass, swaps)
    result
  end

  # A declaration that cannot be run again -- one that raises the second
  # time -- leaves the mutated one to be settled without it, against what
  # the file's load left behind, which may keep the original beside it.
  def self.rerun_original(klass, origin, original)
    redeclare(klass, origin, rerun: true) do
      original.run(klass, origin)
    rescue StandardError => e
      Evilution::Diagnostic.warn(
        "[evilution] could not run #{origin.file}:#{origin.lines.first} again (#{e.class}: #{e.message}); " \
        "its mutations are applied beside what it registered when the file loaded"
      )
    end
  end

  def self.key(klass, origin)
    [klass, origin.file, origin.lines.first]
  end

  def self.ledger
    @ledger ||= Ledger.new({}, {})
  end

  # `validates` also lists its validator for reflection (`Model.validators`),
  # once per class; the old one is exchanged for the new there too, or
  # dropped when nothing took its place. A new one that takes no old one's
  # place is listed by the class alone, so it is added to the lists of its
  # descendants, which took theirs from the class when they were defined.
  def self.swap_validators(klass, swaps)
    return unless klass.respond_to?(:_validators)

    pairs = swaps.map { |old, new| [old && old.filter, new && new.filter] }
    [klass, *descendants(klass)].each do |target|
      target._validators.each do |attribute, validators|
        pairs.each { |old, new| exchange(validators, old, new, klass._validators.fetch(attribute, [])) }
      end
    end
  end

  def self.exchange(validators, old, new, listed)
    return validators << new if old.nil? && Identity.member?(listed, new) && !Identity.member?(validators, new)

    index = validators.index { |validator| validator.equal?(old) }
    return unless index
    return validators.delete_at(index) unless new

    validators.reject! { |validator| validator.equal?(new) }
    validators[validators.index { |validator| validator.equal?(old) }] = new
  end

  def self.descendants(klass)
    klass.subclasses.flat_map { |subclass| [subclass, *descendants(subclass)] }
  end

  private_class_method :redeclare, :rerun_original, :key, :ledger, :swap_validators, :exchange, :descendants

  # What earlier calls did, by declaration -- [class, file, first line]:
  # the callbacks each registered, and, for one that registered none, the
  # callback of each chain that followed what it registered before, if any.
  Ledger = Data.define(:registered, :vacancies)
  private_constant :Ledger

  # The declaration as written in the file, and the binding of the class body
  # it is written in, if known.
  Original = Data.define(:source, :body) do
    def run(klass, origin)
      return klass.class_eval(source, origin.file, origin.lines.first) unless body

      body.eval(source, origin.file, origin.lines.first)
    end
  end
  private_constant :Original

  Equivalence = Evilution::Integration::Loading::CallbackEquivalence
  private_constant :Equivalence

  # Callbacks are told apart by identity throughout: two that compare equal
  # are still two registrations.
  module Identity
    def self.member?(callbacks, callback)
      callbacks.any? { |candidate| candidate.equal?(callback) }
    end

    def self.without(callbacks, others)
      callbacks.reject { |callback| member?(others, callback) }
    end
  end
  private_constant :Identity

  # Rebuilds the chains of a class and its descendants after one declaration
  # has run again.
  class Settlement
    def initialize(klass, origin, ledger, key, rerun:)
      @klass = klass
      @origin = origin
      @registered = ledger.registered
      @vacancies = ledger.vacancies[key] ||= {}
      @key = key
      @rerun = rerun
    end

    # before: { chain name => callbacks } as they were. Returns [old, new]
    # callback pairs for what changed hands, nil standing for no callback.
    def call(before)
      previous = @registered[@key]
      mine = []
      changed = false
      swaps = before.flat_map do |name, callbacks|
        stale, fresh = settle(name, callbacks, previous)
        mine.concat(fresh)
        changed ||= !stale.empty?
        pairs(stale, fresh)
      end
      @registered[@key] = mine if changed || !mine.empty?
      swaps
    end

    private

    def pairs(stale, fresh)
      return stale.zip(fresh) if stale.length >= fresh.length

      fresh.zip(stale).map(&:reverse)
    end

    def settle(name, before, previous)
      after = @klass.__callbacks[name].to_a
      fresh = Identity.without(after, before)
      claimed = @rerun ? claim(name, before, fresh) : []
      stale = before.select { |callback| stale?(callback, previous, claimed) || !Identity.member?(after, callback) }
      return [[], []] if fresh.empty? && stale.empty?

      order = reorder(name, before, stale, fresh)
      @klass.send(:__update_callbacks, name) { |target, chain| rebuild(target, name, chain, order, after) }
      [stale, fresh]
    end

    # What this declaration registered before: what an earlier call recorded
    # or, the first time, what was written on its lines -- unless an earlier
    # call for another declaration put it there. Run as written in the file,
    # the declaration registers the same callbacks as on load, so those are
    # what it registered too; a mutated one registers others, whose procs may
    # say they were written anywhere.
    def stale?(callback, previous, claimed)
      return Identity.member?(previous, callback) if previous
      return false if Identity.member?(@registered.values.flatten, callback)

      @origin.declared?(callback) || Identity.member?(claimed, callback)
    end

    # The callbacks the declaration, run as written, registered on load: for
    # each it registers now, the last equal one before it that no other is
    # taken for. One the class inherited was registered by its parent, and
    # one recorded for another declaration by that declaration.
    def claim(name, before, fresh)
      others = inherited(name) + @registered.values.flatten
      candidates = Identity.without(before, others).reverse
      fresh.each_with_object([]) do |callback, claimed|
        match = candidates.find { |other| !Identity.member?(claimed, other) && Equivalence.call(other, callback) }
        claimed << match if match
      end
    end

    def inherited(name)
      parent = @klass.superclass if @klass.is_a?(Class)
      parent.respond_to?(:__callbacks) ? parent.__callbacks[name].to_a : []
    end

    # The new callbacks take the place of the first old one. With no old one
    # to replace they go where an earlier run that registered nothing left a
    # place, or stay where the declaration put them, at the end.
    def reorder(name, before, stale, fresh)
      return refill(name, before, fresh) if stale.empty?

      vacate(name, before, stale) if fresh.empty?
      before.flat_map do |callback|
        next fresh if callback.equal?(stale.first)

        Identity.member?(stale, callback) ? [] : [callback]
      end
    end

    def vacate(name, before, stale)
      start = before.index { |callback| callback.equal?(stale.first) }
      @vacancies[name] = before.drop(start).find { |callback| !Identity.member?(stale, callback) }
    end

    def refill(name, before, fresh)
      following = @vacancies.delete(name)
      index = following && before.index { |callback| callback.equal?(following) }
      return before + fresh unless index

      before.take(index) + fresh + before.drop(index)
    end

    def rebuild(target, name, chain, order, after)
      own = Identity.without(chain.to_a, after)
      chain.clear
      (order + own).each { |callback| chain.append(callback) }
      target.send(:set_callbacks, name, chain)
    end
  end
  private_constant :Settlement

  # Where a declaration is written, and whether a callback came from there.
  class Origin
    attr_reader :file, :lines

    def initialize(file, lines)
      @file = canonical(file)
      @lines = lines
    end

    def declared?(callback)
      procs_of(callback).any? { |callable| here?(callable.source_location) }
    end

    private

    def procs_of(callback)
      conditions = CONDITIONS.flat_map { |ivar| Array(callback.instance_variable_get(ivar)) }
      [callback.filter, *conditions].grep(Proc)
    end

    def here?(location)
      !location.nil? && canonical(location.first) == @file && @lines.cover?(location.last)
    end

    # The same file may have been loaded through a symlinked path.
    def canonical(path)
      File.realpath(path)
    rescue SystemCallError
      File.expand_path(path)
    end
  end
  private_constant :Origin
end
