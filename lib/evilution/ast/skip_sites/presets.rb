# frozen_string_literal: true

require_relative "../skip_sites"
require_relative "logging"
require_relative "debug_output"
require_relative "error_messages"
require_relative "requires"

# The presets by name. Each answers #covers?(chain): whether the node a
# mutation changes, followed by its ancestors nearest first, lies inside one
# of its sites in a way that only changes what the site reports.
#
# Listed in the order a skipped mutation is attributed: one that two presets
# cover is counted under the first.
module Evilution::AST::SkipSites::Presets
  ALL = {
    logging: Evilution::AST::SkipSites::Logging,
    debug_output: Evilution::AST::SkipSites::DebugOutput,
    error_messages: Evilution::AST::SkipSites::ErrorMessages,
    requires: Evilution::AST::SkipSites::Requires
  }.freeze

  def self.names
    ALL.keys
  end

  # names: Symbols from .names; the presets come back in attribution order.
  def self.build(names)
    ALL.filter_map { |name, preset| preset.new if names.include?(name) }
  end
end
