# frozen_string_literal: true

require_relative "../info_tool"

module Evilution::MCP::InfoTool::ErrorMapper
  module_function

  def type_for(error)
    case error
    when Evilution::ConfigError then "config_error"
    when Evilution::ParseError  then "parse_error"
    else "runtime_error"
    end
  end
end
