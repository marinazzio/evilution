# frozen_string_literal: true

require_relative "../mutate_tool"

module Evilution::MCP::MutateTool::ErrorPayload
  def self.build(error)
    type = case error
           when Evilution::ConfigError then "config_error"
           when Evilution::ParseError  then "parse_error"
           else "runtime_error"
           end

    payload = { type: type, message: error.message }
    payload[:file] = error.file if error.file
    { error: payload }
  end
end
