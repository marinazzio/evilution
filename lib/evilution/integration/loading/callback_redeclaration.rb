# frozen_string_literal: true

require_relative "../loading"

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
# "Last time" is the file's own load the first time round, and those
# callbacks are recognised by where their procs were written (or by having
# been dropped as duplicates). After that the module goes by what it
# registered itself: the source it is called from has its other class-body
# calls blanked, multi-line ones included, so a proc created there reports a
# line that may belong to another declaration of the real file.
module Evilution::Integration::Loading::CallbackRedeclaration
  CONDITIONS = %i[@if @unless].freeze
  private_constant :CONDITIONS

  # klass: the class whose body the declaration is written in. file, lines:
  # where the declaration is in the file as it was loaded.
  def self.call(klass, file, lines)
    return yield unless klass.respond_to?(:__callbacks)

    before = klass.__callbacks.transform_values(&:to_a)
    result = yield
    swaps = Settlement.new(klass, Origin.new(file, lines), registered).call(before)
    swap_validators(klass, swaps)
    result
  end

  # What earlier calls registered, by declaration:
  # { [class, file, first line] => callbacks }.
  def self.registered
    @registered ||= {}
  end

  # `validates` also lists its validator for reflection (`Model.validators`),
  # once per class; the old one is exchanged for the new there too.
  def self.swap_validators(klass, swaps)
    return unless klass.respond_to?(:_validators)

    pairs = swaps.select { |old, new| old && new }.map { |old, new| [old.filter, new.filter] }
    [klass, *descendants(klass)].each do |target|
      target._validators.each_value do |validators|
        pairs.each { |old, new| exchange(validators, old, new) }
      end
    end
  end

  def self.exchange(validators, old, new)
    return unless validators.any? { |validator| validator.equal?(old) }

    validators.reject! { |validator| validator.equal?(new) }
    validators[validators.index { |validator| validator.equal?(old) }] = new
  end

  def self.descendants(klass)
    klass.subclasses.flat_map { |subclass| [subclass, *descendants(subclass)] }
  end

  private_class_method :registered, :swap_validators, :exchange, :descendants

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
    def initialize(klass, origin, registered)
      @klass = klass
      @origin = origin
      @registered = registered
      @key = [klass, origin.file, origin.lines.first]
    end

    # before: { chain name => callbacks } as they were. Returns [old, new]
    # callback pairs for what changed hands.
    def call(before)
      previous = @registered[@key]
      mine = []
      swaps = before.flat_map do |name, callbacks|
        stale, fresh = settle(name, callbacks, previous)
        mine.concat(fresh)
        stale.zip(fresh)
      end
      @registered[@key] = mine unless mine.empty?
      swaps
    end

    private

    def settle(name, before, previous)
      after = @klass.__callbacks[name].to_a
      fresh = Identity.without(after, before)
      return [[], []] if fresh.empty?

      stale = before.select { |callback| stale?(callback, previous) || !Identity.member?(after, callback) }
      order = reorder(before, stale, fresh)
      @klass.send(:__update_callbacks, name) { |target, chain| rebuild(target, name, chain, order, after) }
      [stale, fresh]
    end

    # What this declaration registered before: what an earlier call recorded
    # or, the first time, what was written on its lines -- unless an earlier
    # call for another declaration put it there.
    def stale?(callback, previous)
      return Identity.member?(previous, callback) if previous

      @origin.declared?(callback) && !Identity.member?(@registered.values.flatten, callback)
    end

    # The new callbacks take the place of the first old one; with no old one
    # to replace they stay where the declaration put them, at the end.
    def reorder(before, stale, fresh)
      return before + fresh if stale.empty?

      before.flat_map do |callback|
        next fresh if callback.equal?(stale.first)

        Identity.member?(stale, callback) ? [] : [callback]
      end
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
