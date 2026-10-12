# frozen_string_literal: true

require_relative "../loading"
require_relative "own_methods"

# Re-declares one statement of a concern's `included` block on the classes
# that already include the concern, or of its `prepended` block on those that
# prepend it.
#
# A mutation inside `included do ... scope :published, -> { } ... end` has two
# audiences. Classes that include the concern later run the whole block, so
# registering the mutated block is enough for them. Classes that already
# include it ran the original, and running the whole block on them again
# would add its validations and callbacks a second time.
#
# So the source evilution evaluates guards every other call of the block with
# `skipping?` and ends the block with `call(self)`: the block is run once more
# on each existing includer with the guard up, and only the mutated
# declaration takes effect there. What the block holds besides calls -- a
# method definition, an assignment -- runs again as well, which is how a
# mutated method of the block reaches those classes. A method the class has
# defined itself over one of the block's is kept (OwnMethods). See
# BodyCallNeutralizer.
module Evilution::Integration::Loading::ConcernRedeclaration
  KEY = :evilution_concern_redeclaration
  BLOCKS = { included: :@_included_block, prepended: :@_prepended_block }.freeze

  # Called through UnboundMethods: ObjectSpace hands over every class in the
  # VM, and one that defines `include?` or `superclass` of its own for its
  # own purposes must not be asked that question.
  INCLUDES = Module.instance_method(:include?)
  SUPERCLASS = Class.instance_method(:superclass)
  SINGLETON = Module.instance_method(:singleton_class?)
  ANCESTORS = Module.instance_method(:ancestors)
  private_constant :KEY, :BLOCKS, :INCLUDES, :SUPERCLASS, :SINGLETON, :ANCESTORS

  def self.skipping?
    Thread.current[KEY] == true
  end

  # `hook` names the block: `:included` or `:prepended`.
  def self.call(concern, hook = :included)
    ivar = BLOCKS.fetch(hook)
    return unless concern.instance_variable_defined?(ivar)

    block = concern.instance_variable_get(ivar)
    takers(concern, prepended: hook == :prepended).each { |klass| redeclare(klass, block) }
  end

  # The classes that took the concern themselves, by including it or by
  # prepending it; a subclass inherits what its parent declares.
  def self.takers(concern, prepended:)
    ObjectSpace.each_object(Class).select do |klass|
      next false if SINGLETON.bind_call(klass) || !INCLUDES.bind_call(klass, concern)

      parent = SUPERCLASS.bind_call(klass)
      inherited = !parent.nil? && INCLUDES.bind_call(parent, concern)
      !inherited && prepended?(klass, concern) == prepended
    end
  end

  # A prepended module comes before the class in its ancestors, an included
  # one after it.
  def self.prepended?(klass, concern)
    ancestors = ANCESTORS.bind_call(klass)
    ancestors.index(concern) < ancestors.index(klass)
  end

  def self.redeclare(klass, block)
    previous = Thread.current[KEY]
    Thread.current[KEY] = true
    Evilution::Integration::Loading::OwnMethods.keeping(klass, block.source_location.first) do
      klass.class_eval(&block)
    end
  ensure
    Thread.current[KEY] = previous
  end

  private_class_method :takers, :prepended?, :redeclare
end
