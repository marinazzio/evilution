# frozen_string_literal: true

require_relative "../mutate_tool"
require_relative "option_parser"
require_relative "../../config"

module Evilution::MCP::MutateTool::ConfigBuilder
  def self.build(files:, line_ranges:, params:)
    # Preload is disabled for MCP invocations: `require`-ing Rails into the
    # long-lived MCP server would poison subsequent runs against other
    # projects. MCP users who want the speedup should use the CLI.
    opts = { target_files: files, line_ranges: line_ranges, format: :json, quiet: true, preload: false }
    opts[:skip_config_file] = true if params[:skip_config]
    opts[:spec_files] = params[:spec] if params[:spec]
    Evilution::MCP::MutateTool::OptionParser::PASSTHROUGH_KEYS.each do |key|
      opts[key] = params[key] unless params[key].nil?
    end
    Evilution::Config.new(**opts)
  end
end
