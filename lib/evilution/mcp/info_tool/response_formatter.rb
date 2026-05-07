# frozen_string_literal: true

require "json"
require_relative "../info_tool"
require_relative "error_mapper"

module Evilution::MCP::InfoTool::ResponseFormatter
  module_function

  # Wraps the payload as a successful MCP text response and injects the
  # outer-envelope schema_version so agents that cache contracts can detect
  # incompatible servers. Existing schema_version keys in the payload are
  # preserved (e.g. session JSON keeps its own schema_version unchanged).
  def success(payload)
    versioned = inject_schema_version(payload)
    ::MCP::Tool::Response.new([{ type: "text", text: ::JSON.generate(versioned) }])
  end

  def inject_schema_version(payload)
    return payload unless payload.is_a?(Hash)
    return payload if payload.key?("schema_version") || payload.key?(:schema_version)

    { "schema_version" => Evilution::MCP::CONTRACT_VERSION }.merge(payload)
  end
  private_class_method :inject_schema_version

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
