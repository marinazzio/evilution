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
# `p` and `pp` return what they print and a stream's `write` the number of
# bytes written, so they are sites only where their value goes unused (see
# Nodes.value_dropped?): as the last statement of a method, or inside an
# expression, a changed argument changes the value. The others return nil
# whatever they print.
#
# Within a site, mutations are skipped by the same rule as for log lines
# (see Logging): the call itself and its receiver only where its value goes
# unused.
class Evilution::AST::SkipSites::DebugOutput
  PRINTERS = %i[puts print printf warn].freeze
  VALUE_PRINTERS = %i[p pp].freeze
  STREAM_PRINTERS = %i[puts print printf].freeze
  STREAM_WRITERS = %i[write].freeze
  STREAMS = %w[stdout stderr STDOUT STDERR].freeze
  private_constant :PRINTERS, :VALUE_PRINTERS, :STREAM_PRINTERS, :STREAM_WRITERS, :STREAMS

  def name
    :debug_output
  end

  # chain: the mutated node, then its ancestors, nearest first.
  def covers?(chain)
    chain.each_index.any? { |index| site?(chain, index) && covered_in_site?(chain, index) }
  end

  private

  def site?(chain, index)
    node = chain[index]
    return false unless node.is_a?(Prism::CallNode)
    return true if Evilution::AST::SkipSites::Nodes.kernel_call?(node, PRINTERS) || stream_call?(node, STREAM_PRINTERS)

    value_printer?(node) && Evilution::AST::SkipSites::Nodes.value_dropped?(chain, index)
  end

  def value_printer?(call)
    Evilution::AST::SkipSites::Nodes.kernel_call?(call, VALUE_PRINTERS) || stream_call?(call, STREAM_WRITERS)
  end

  def stream_call?(call, names)
    receiver = call.receiver
    return false unless names.include?(call.name)

    stream = receiver.is_a?(Prism::GlobalVariableReadNode) || receiver.is_a?(Prism::ConstantReadNode)
    stream && STREAMS.include?(Evilution::AST::SkipSites::Nodes.receiver_name(receiver))
  end

  def covered_in_site?(chain, site_index)
    call = chain[site_index]
    parts = call.arguments ? call.arguments.arguments : []
    Evilution::AST::SkipSites::Message.covered_in_call(chain, site_index, parts)
  end
end
