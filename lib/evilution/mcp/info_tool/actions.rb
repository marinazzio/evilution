# frozen_string_literal: true

require "mcp"
require_relative "../../mcp"

class Evilution::MCP::InfoTool < MCP::Tool; end unless defined?(Evilution::MCP::InfoTool)

module Evilution::MCP::InfoTool::Actions
end

unless defined?(Evilution::MCP::InfoTool::Actions::Base)
  class Evilution::MCP::InfoTool::Actions::Base # rubocop:disable Lint/EmptyClass
  end
end

require_relative "../info_tool"
