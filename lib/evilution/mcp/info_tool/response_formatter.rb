# frozen_string_literal: true

require "json"
require_relative "../info_tool"
require_relative "error_mapper"

module Evilution::MCP::InfoTool::ResponseFormatter
  module_function

  def success(payload)
    ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(payload) }])
  end

  def error(type, message)
    ::MCP::Tool::Response.new(
      [{ type: "text", text: ::JSON.generate({ error: { type: type, message: message } }) }],
      error: true
    )
  end

  def error_for(exception)
    error(Evilution::MCP::InfoTool::ErrorMapper.type_for(exception), exception.message)
  end
end
