# frozen_string_literal: true

require_relative "../operator"

# Take the wait out of a sleep whose duration is not a literal:
# `sleep delay` becomes `sleep 0`.
#
# A survivor means the pause decides nothing an example observes. A killed
# mutant means the suite depends on wall-clock time, which is worth knowing
# too.
#
# A literal duration (`sleep 5`, `sleep 0.5`) is left to the literal
# operators, which already take it to zero. Only `Kernel#sleep` is touched: a
# `sleep` sent to another receiver may be something else.
class Evilution::Mutator::Operator::SleepToZero < Evilution::Mutator::Base
  LITERAL_DURATIONS = [Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode].freeze
  KERNEL = %w[Kernel ::Kernel].freeze

  def visit_call_node(node)
    duration = duration_of(node)
    add_mutation(offset: duration.location.start_offset, length: duration.location.length, replacement: "0", node:) if duration

    super
  end

  private

  # The single argument of a `sleep` call, when it is one this operator
  # replaces.
  def duration_of(node)
    return unless node.name == :sleep && kernel_call?(node) && node.arguments

    arguments = node.arguments.arguments
    return unless arguments.one?

    duration = arguments.first
    duration unless duration.is_a?(Prism::SplatNode) || LITERAL_DURATIONS.include?(duration.class)
  end

  def kernel_call?(node)
    node.receiver.nil? || KERNEL.include?(node.receiver.slice)
  end
end
