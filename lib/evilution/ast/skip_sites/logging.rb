# frozen_string_literal: true

require "prism"
require_relative "../skip_sites"
require_relative "nodes"
require_relative "message"

# Log lines and deprecation warnings: what the code reports about its work,
# not the work.
#
# A site is a call of a log level (`debug info warn error fatal unknown add
# log`) on a receiver named `logger` -- `logger`, `@logger`, `LOGGER`,
# `Rails.logger`, `config.logger` -- or of `warn` / `deprecation_warning` on
# a deprecator (`ActiveSupport::Deprecation`, `ActiveSupport.deprecator`,
# `Rails.deprecator`, `deprecator`), or `Kernel#warn` with `category:
# :deprecated`. The condition guarding a log line is not part of it, nor is
# a predicate such as `logger.debug?`.
#
# A mutation inside a site is skipped when it changes the message alone:
# literal text of the message, or anything inside an argument (or the block)
# that only reads. A mutation of the call itself, its receiver, or code
# between the two -- deleting the line, say -- is skipped when every
# argument only reads; were one to change state (`logger.info(queue.pop!)`),
# deleting the line would change more than the log.
class Evilution::AST::SkipSites::Logging
  LEVELS = %i[debug info warn error fatal unknown add log].freeze
  DEPRECATION_WARNINGS = %i[warn deprecation_warning].freeze
  WARN = %i[warn].freeze
  private_constant :LEVELS, :DEPRECATION_WARNINGS, :WARN

  def name
    :logging
  end

  # chain: the mutated node, then its ancestors, nearest first.
  def covers?(chain)
    chain.each_with_index.any? { |node, index| site?(node) && covered_in_site?(chain, index) }
  end

  private

  def site?(node)
    return false unless node.is_a?(Prism::CallNode)

    log_line?(node) || deprecation_warning?(node) || deprecated_category_warn?(node)
  end

  def log_line?(call)
    LEVELS.include?(call.name) && named?(call.receiver, "logger", "LOGGER")
  end

  def deprecation_warning?(call)
    DEPRECATION_WARNINGS.include?(call.name) && named?(call.receiver, "deprecator", "Deprecation")
  end

  def deprecated_category_warn?(call)
    Evilution::AST::SkipSites::Nodes.kernel_call?(call, WARN) && deprecated_category?(call.arguments)
  end

  def deprecated_category?(arguments)
    return false unless arguments

    arguments.arguments.grep(Prism::KeywordHashNode).any? do |hash|
      hash.elements.any? { |element| category_deprecated?(element) }
    end
  end

  def category_deprecated?(element)
    element.is_a?(Prism::AssocNode) &&
      symbol_named?(element.key, "category") && symbol_named?(element.value, "deprecated")
  end

  def symbol_named?(node, name)
    node.is_a?(Prism::SymbolNode) && node.unescaped == name
  end

  # A receiver goes by no name when there is none.
  def named?(receiver, *names)
    names.include?(Evilution::AST::SkipSites::Nodes.receiver_name(receiver))
  end

  def covered_in_site?(chain, site_index)
    Evilution::AST::SkipSites::Message.covered_in_call(chain, site_index, message_parts(chain[site_index]))
  end

  def message_parts(call)
    arguments = call.arguments ? call.arguments.arguments : []
    call.block ? arguments + [call.block] : arguments
  end
end
