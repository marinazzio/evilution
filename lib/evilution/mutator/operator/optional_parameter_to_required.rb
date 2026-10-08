# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Drop the default of an optional positional parameter, making it required:
# `def f(a = 1)` becomes `def f(a)`.
#
# A survivor means no example calls the method without that argument, so the
# default is never exercised and the value it supplies is unasserted. Callers
# that pass the argument are unaffected, which is what separates this from a
# mutation that breaks every call site.
#
# Optional parameters have to sit side by side, so only the ends of a run of
# them are mutated; a required parameter in the middle would split it in two.
# The first can always join the required parameters before it. The last can
# join those after it, unless a rest parameter follows: a required parameter
# cannot stand between an optional one and `*rest`. The rest of the signature
# stays as written.
# KeywordArgument owns optional keyword parameters. Blocks are left alone: a
# block ignores arity, so a missing argument arrives as nil rather than raising,
# and making its parameter required would change nothing.
class Evilution::Mutator::Operator::OptionalParameterToRequired < Evilution::Mutator::Base
  def visit_def_node(node)
    parameters = node.parameters
    mutable_optionals(parameters).each { |optional| require_parameter(optional) } if parameters

    super
  end

  private

  def mutable_optionals(parameters)
    optionals = parameters.optionals
    return optionals.first(1) if parameters.rest

    [optionals.first, optionals.last].compact.uniq
  end

  def require_parameter(node)
    location = node.location
    name_loc = node.name_loc

    add_mutation(
      offset: location.start_offset,
      length: location.length,
      replacement: byteslice_source(name_loc.start_offset, name_loc.length),
      node: node
    )
  end
end
