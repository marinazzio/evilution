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
# The target of an operator write is stripped as well: `Config::LIMIT ||= x`
# becomes `LIMIT ||= x`, defining the constant where the code stands. A
# top-level path (`::LIMIT`) has no namespace to strip.
class Evilution::Mutator::Operator::ConstantNamespaceStrip < Evilution::Mutator::Base
  def visit_constant_path_node(node)
    replace_span(node: node, target: node, replacement: name_source(node)) if node.parent
    super
  end

  private

  def name_source(node)
    location = node.name_loc
    byteslice_source(location.start_offset, location.length)
  end
end
