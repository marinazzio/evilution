# frozen_string_literal: true

require_relative "../operator"

# Assign `nil` to a constant instead of its value: `LIMIT = 10` becomes
# `LIMIT = nil`.
#
# A survivor means nothing the tests run depends on what the constant holds.
# The literal operators go on to change the value piece by piece; this one
# takes it away whole, whatever it is — a literal, a call, a lambda.
#
# It works on constant-write subjects, each being one assignment, and does
# not look inside the value: a constant assigned there (in the block of a
# `Class.new`) is a subject of its own. A constant already assigned `nil`
# has nothing to lose.
#
# Code that read the constant while the file first loaded keeps the old
# value (see Subject), so only what reads it when called sees the mutant.
class Evilution::Mutator::Operator::ConstantWriteToNil < Evilution::Mutator::Base
  def self.subject_kinds
    %i[constant_write]
  end

  def visit_constant_write_node(node)
    mutate_to_nil(node, target: node.value)
  end

  def visit_constant_path_write_node(node)
    mutate_to_nil(node, target: node.value)
  end
end
