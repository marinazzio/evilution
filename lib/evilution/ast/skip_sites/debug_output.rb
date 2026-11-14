# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"
require_relative "nodes"
require_relative "message"

# Console output: `puts`, `print`, `printf`, `warn`, `p` and `pp` sent to no
# receiver or to Kernel, and `puts` / `print` / `printf` / `write` sent to
# `$stdout`, `$stderr`, `STDOUT` or `STDERR`. Output that is the program's
# job -- a CLI printing its result -- is console output all the same, which
# is why this preset stands apart from logging.
#
# `p` and `pp` return what they print, so they are sites only as a statement
# followed by another one in the same body, where their value is dropped;
# as the last statement of a body, or inside an expression, their value may
# be used. The others return nil wherever they stand.
#
# Within a site, mutations are skipped by the same rule as for log lines
# (see Logging).
class Evilution::AST::SkipSites::DebugOutput
  PRINTERS = %i[puts print printf warn].freeze
  VALUE_PRINTERS = %i[p pp].freeze
  STREAM_WRITERS = %i[puts print printf write].freeze
  STREAMS = %w[stdout stderr STDOUT STDERR].freeze
  private_constant :PRINTERS, :VALUE_PRINTERS, :STREAM_WRITERS, :STREAMS

  def name
    :debug_output
  end

  # chain: the mutated node, then its ancestors, nearest first.
  def covers?(chain)
    chain.each_with_index.any? { |node, index| site?(node, chain[index + 1]) && covered_in_site?(chain, index) }
  end

  private

  def site?(node, parent)
    return false unless node.is_a?(Prism::CallNode)

    Evilution::AST::SkipSites::Nodes.kernel_call?(node, PRINTERS) ||
      stream_write?(node) ||
      (Evilution::AST::SkipSites::Nodes.kernel_call?(node, VALUE_PRINTERS) && value_dropped?(node, parent))
  end

  def stream_write?(call)
    receiver = call.receiver
    return false unless STREAM_WRITERS.include?(call.name)

    stream = receiver.is_a?(Prism::GlobalVariableReadNode) || receiver.is_a?(Prism::ConstantReadNode)
    stream && STREAMS.include?(Evilution::AST::SkipSites::Nodes.receiver_name(receiver))
  end

  def value_dropped?(call, parent)
    return false unless parent.is_a?(Prism::StatementsNode)

    !Evilution::AST::SkipSites::Nodes.same?(parent.body.last, call)
  end

  def covered_in_site?(chain, site_index)
    call = chain[site_index]
    parts = call.arguments ? call.arguments.arguments : []
    Evilution::AST::SkipSites::Message.covered_in_call(chain, site_index, parts)
  end
end
