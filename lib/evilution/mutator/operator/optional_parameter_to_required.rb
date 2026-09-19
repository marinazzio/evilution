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
# Ruby allows a required parameter to follow an optional one, so each optional
# is mutated on its own and the rest of the signature stays as written.
# KeywordArgument owns optional keyword parameters. Blocks are left alone: a
# block ignores arity, so a missing argument arrives as nil rather than raising,
# and making its parameter required would change nothing.
class Evilution::Mutator::Operator::OptionalParameterToRequired < Evilution::Mutator::Base
  def visit_def_node(node)
    parameters = node.parameters
    parameters.optionals.each { |optional| require_parameter(optional) } if parameters

    super
  end

  private

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
