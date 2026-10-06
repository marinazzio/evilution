# frozen_string_literal: true

require_relative "../loading"

# Re-declares one statement of a concern's `included` block on the classes
# that already include the concern.
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
# declaration takes effect there. See BodyCallNeutralizer.
module Evilution::Integration::Loading::ConcernRedeclaration
  KEY = :evilution_concern_redeclaration
  INCLUDED_BLOCK = :@_included_block

  # Called through UnboundMethods: ObjectSpace hands over every class in the
  # VM, and one that defines `include?` or `superclass` of its own for its
  # own purposes must not be asked that question.
  INCLUDES = Module.instance_method(:include?)
  SUPERCLASS = Class.instance_method(:superclass)
  SINGLETON = Module.instance_method(:singleton_class?)
  private_constant :KEY, :INCLUDED_BLOCK, :INCLUDES, :SUPERCLASS, :SINGLETON

  def self.skipping?
    Thread.current[KEY] == true
  end

  def self.call(concern)
    return unless concern.instance_variable_defined?(INCLUDED_BLOCK)

    block = concern.instance_variable_get(INCLUDED_BLOCK)
    includers(concern).each { |klass| redeclare(klass, block) }
  end

  # The classes that include the concern themselves; a subclass inherits what
  # its parent declares.
  def self.includers(concern)
    ObjectSpace.each_object(Class).select do |klass|
      next false if SINGLETON.bind_call(klass) || !INCLUDES.bind_call(klass, concern)

      parent = SUPERCLASS.bind_call(klass)
      parent.nil? || !INCLUDES.bind_call(parent, concern)
    end
  end

  def self.redeclare(klass, block)
    previous = Thread.current[KEY]
    Thread.current[KEY] = true
    klass.class_eval(&block)
  ensure
    Thread.current[KEY] = previous
  end

  private_class_method :includers, :redeclare
end
