# frozen_string_literal: true

require_relative "../mutator"

# Extended by the operators that mutate a value wherever it is written, so
# that they also run on the value of a constant assignment: a literal in
# `LIMIT = 10` or in `DEFAULTS = { size: 1 }` is as much a literal as one in
# a method body, and so is a call in `LIMIT = ENV["LIMIT"].to_i`.
#
# A method defined in the value (`Handler = Class.new do def call ... end`)
# is a subject of its own, so the operator leaves it to that subject rather
# than report its mutations against the constant.
module Evilution::Mutator::ConstantValueSubjects
  def self.extended(operator)
    operator.include(Visits)
  end

  def subject_kinds
    super + %i[constant_write]
  end

  module Visits
    def visit_def_node(node)
      super unless constant_value?
    end

    private

    def constant_value?
      @subject.kind == :constant_write
    end

    # The `freeze` of a constant's value is freeze_removal's to drop: under
    # that name, and against the method anchoring the class body. A call
    # operator running on the constant would otherwise make the same bytes
    # first and take them over in dedup.
    def constant_value_freeze?(call)
      constant_value? && call.name == :freeze && call.arguments.nil?
    end
  end
end
