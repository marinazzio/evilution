# frozen_string_literal: true

require_relative "base"
require_relative "../status_glossary"

class Evilution::MCP::InfoTool::Actions::Statuses < Evilution::MCP::InfoTool::Actions::Base
  def self.call(**)
    success("statuses" => Evilution::MCP::InfoTool::StatusGlossary.entries)
  end
end
