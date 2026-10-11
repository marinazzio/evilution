# frozen_string_literal: true

require_relative "../operator"

# Strip the namespace off a constant path: `Config::LIMIT` becomes `LIMIT`.
# A longer path is stripped at each level, so `App::Config::LIMIT` gives
# both `LIMIT` and `Config::LIMIT`.
#
# The bare name is looked up from where the code stands instead of inside
# the namespace. It either finds another constant or raises NameError; a
# survivor means the same constant is reachable without the qualifier, or
# that nothing depends on which one is found. A namespace given by an
# expression (`self.class::LIMIT`) is stripped too — there the survivor says
# no test overrides the constant in a subclass.
#
# A top-level path (`::LIMIT`) has no namespace to strip. The target of an
# operator write (`Config::LIMIT ||= x`) is left alone: bare, `LIMIT ||= x`
# is a dynamic constant assignment inside a method. Prism lets it through,
# so the parse check would not catch it, but the parse.y parser rejects it
# with a SyntaxError.
class Evilution::Mutator::Operator::ConstantNamespaceStrip < Evilution::Mutator::Base
  def call(subject, **)
    @write_targets = Set.new
    super
  end

  def visit_constant_path_or_write_node(node)
    @write_targets.add(node.target)
    super
  end

  def visit_constant_path_and_write_node(node)
    @write_targets.add(node.target)
    super
  end

  def visit_constant_path_operator_write_node(node)
    @write_targets.add(node.target)
    super
  end

  def visit_constant_path_node(node)
    replace_span(node: node, target: node, replacement: name_source(node)) if strippable?(node)
    super
  end

  private

  def strippable?(node)
    node.parent && !@write_targets.include?(node)
  end

  def name_source(node)
    location = node.name_loc
    byteslice_source(location.start_offset, location.length)
  end
end
