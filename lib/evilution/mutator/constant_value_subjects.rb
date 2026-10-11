# frozen_string_literal: true

require_relative "../mutator"

# Extended by the operators that mutate a value wherever it is written, so
# that they also run on the value of a constant assignment: a literal in
# `LIMIT = 10` or in `DEFAULTS = { size: 1 }` is as much a literal as one in
# a method body.
module Evilution::Mutator::ConstantValueSubjects
  def subject_kinds
    super + %i[constant_write]
  end
end
