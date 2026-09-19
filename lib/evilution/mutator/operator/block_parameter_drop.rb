# frozen_string_literal: true

require "prism"

require_relative "../operator"

# Drop the single parameter of a block: `users.each { |u| touch(u) }` becomes
# `users.each { touch(u) }`.
#
# A block tolerates being handed more arguments than it declares, so the mutant
# runs until the body reads the dropped name, where it raises NameError. A
# survivor therefore means the block never ran on a path the suite asserts —
# the collection was empty, or the call was stubbed away.
#
# Not to be confused with BlockParamRemoval, which removes a method's `&block`
# parameter from its signature.
#
# Two shapes are deliberately left alone. A parameter the body never reads makes
# the mutation behaviour-preserving, so it would survive every suite and report
# a coverage gap that is not there. A lambda checks its arity, so dropping its
# parameter raises ArgumentError on every call, whatever the body does.
class Evilution::Mutator::Operator::BlockParameterDrop < Evilution::Mutator::Base
  def visit_block_node(node)
    drop_parameter(node)
    super
  end

  private

  def drop_parameter(node)
    return unless droppable?(node)

    location = node.parameters.location
    leading = leading_space(location)

    add_mutation(
      offset: location.start_offset - leading,
      length: location.length + leading,
      replacement: "",
      node: node
    )
  end

  def droppable?(node)
    parameters = node.parameters
    return false unless parameters.is_a?(Prism::BlockParametersNode)
    return false unless parameters.locals.empty?

    names = single_parameter_names(parameters.parameters)
    names.any? { |name| body_reads?(node.body, name) }
  end

  # The space the block keyword leaves in front of the parameters goes with
  # them, so `{ |u| body }` mutates to `{ body }` and `do |u|` to `do` rather
  # than leaving a double space or a trailing one.
  def leading_space(location)
    preceding = @file_source.byteslice(location.start_offset - 1, 1)
    preceding == " " ? 1 : 0
  end

  # The names bound by a lone required parameter, which is either a plain name
  # or a destructuring target (`|(key, value)|`). Anything else — a second
  # parameter, an optional, a rest, a keyword, a block pass, or the implicit
  # rest Prism reports for the trailing comma in `|key,|` — means this is not a
  # single-parameter block, and numbered parameters carry no node to remove.
  def single_parameter_names(parameters)
    return [] unless parameters.is_a?(Prism::ParametersNode)
    return [] unless parameters.requireds.length == 1
    return [] unless other_parameters_absent?(parameters)

    parameter_names(parameters.requireds.first)
  end

  # Post-required parameters are not checked: block syntax only produces them
  # after a rest parameter, which is rejected here anyway.
  def other_parameters_absent?(parameters)
    parameters.optionals.empty? && parameters.keywords.empty? &&
      parameters.rest.nil? && parameters.keyword_rest.nil? && parameters.block.nil?
  end

  def parameter_names(node)
    case node
    when Prism::RequiredParameterNode then [node.name.to_s]
    when Prism::MultiTargetNode then node.lefts.flat_map { |child| parameter_names(child) }
    else []
    end
  end

  # An underscore-prefixed name announces a parameter that is not meant to be
  # read, so it is treated as unused even where the body happens to mention it.
  def body_reads?(body, name)
    return false if name.start_with?("_")
    return false if body.nil?

    reads_name?(body, name)
  end

  # A nested block shares the enclosing scope, so a read inside one still counts.
  # A nested def does not, and neither does a name that is written before it is
  # read — that binds a fresh local rather than reading the parameter.
  def reads_name?(node, name)
    return true if node.is_a?(Prism::LocalVariableReadNode) && node.name.to_s == name

    node.compact_child_nodes.any? do |child|
      next false if child.is_a?(Prism::DefNode)

      reads_name?(child, name)
    end
  end
end
