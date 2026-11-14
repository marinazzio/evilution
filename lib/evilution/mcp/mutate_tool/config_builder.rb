# frozen_string_literal: true

require_relative "../mutate_tool"
require_relative "option_parser"
require_relative "../../config"
require_relative "../../git/since_scope"

module Evilution::MCP::MutateTool::ConfigBuilder
  def self.build(files:, line_ranges:, params:)
    # Preload is disabled for MCP invocations: `require`-ing Rails into the
    # long-lived MCP server would poison subsequent runs against other
    # projects. MCP users who want the speedup should use the CLI.
    opts = scope(files, line_ranges, params[:since]).merge(format: :json, quiet: true, preload: false)
    opts[:skip_config_file] = true if params[:skip_config]
    opts[:spec_files] = params[:spec] if params[:spec]
    Evilution::MCP::MutateTool::OptionParser::PASSTHROUGH_KEYS.each do |key|
      opts[key] = params[key] unless params[key].nil?
    end
    Evilution::Config.new(**opts)
  end

  # The files and line ranges, limited to the lines changed since the ref
  # given as since.
  def self.scope(files, line_ranges, since)
    paths = Evilution::Git::SinceScope.apply(since, files: files, line_ranges: line_ranges)
    opts = { target_files: paths.files, line_ranges: paths.ranges }
    opts[:since] = since if since
    opts
  end
  private_class_method :scope
end
