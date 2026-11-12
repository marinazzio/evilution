# frozen_string_literal: true

require_relative "../loading"

# Whether two callbacks are what running one declaration twice registers: the
# same kind of callback, with the same filter, under the same conditions. A
# proc is the same when it is written in the same place, an object when it is
# of the same class and holds the same values -- a validator, with the same
# attributes and options. A class is only ever itself, and so are `true`,
# `false` and `nil`.
#
# Values are compared down to a fixed depth and by identity below it, which
# also ends the comparison of a value that holds itself.
module Evilution::Integration::Loading::CallbackEquivalence
  COMPARED = %i[@filter @if @unless].freeze
  PLAIN = [Symbol, String, Numeric, Range, Regexp].freeze
  MAX_DEPTH = 8
  private_constant :COMPARED, :PLAIN, :MAX_DEPTH

  def self.call(callback, other)
    return false if callback.respond_to?(:kind) && callback.kind != other.kind

    COMPARED.all? { |ivar| same?(callback.instance_variable_get(ivar), other.instance_variable_get(ivar), 0) }
  end

  def self.same?(value, other, depth)
    return true if value.equal?(other)
    return false if depth > MAX_DEPTH || value.is_a?(Module)
    return value == other if PLAIN.any? { |type| value.is_a?(type) }

    value.instance_of?(other.class) && same_parts?(parts(value), parts(other), depth + 1)
  end

  def self.same_parts?(values, others, depth)
    values.length == others.length && values.zip(others).all? { |value, other| same?(value, other, depth) }
  end

  # What a value is made of: where a proc was written, the elements of an
  # array, the keys and values of a hash, the instance variables of anything
  # else. A proc that cannot say where it was written is only ever itself.
  def self.parts(value)
    case value
    when Proc then [value.source_location || value.object_id]
    when Array then value
    when Hash then [value.keys, value.values]
    else value.instance_variables.flat_map { |name| [name, value.instance_variable_get(name)] }
    end
  end

  private_class_method :same?, :same_parts?, :parts
end
