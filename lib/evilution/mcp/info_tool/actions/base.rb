# frozen_string_literal: true

require_relative "../actions"
require_relative "../response_formatter"

class Evilution::MCP::InfoTool::Actions::Base
  def self.call(**)
    raise NotImplementedError
  end

  class << self
    private

    def success(payload)
      Evilution::MCP::InfoTool::ResponseFormatter.success(payload)
    end

    def config_error(message)
      Evilution::MCP::InfoTool::ResponseFormatter.error("config_error", message)
    end
  end
end
