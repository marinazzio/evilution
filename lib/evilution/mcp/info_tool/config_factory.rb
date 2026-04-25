# frozen_string_literal: true

require_relative "../info_tool"
require_relative "../../config"

module Evilution::MCP::InfoTool::ConfigFactory
  module_function

  def subjects(files:, line_ranges:, target:, integration:, skip_config:)
    opts = { target_files: files, line_ranges: line_ranges || {} }
    opts[:skip_config_file] = true if skip_config
    opts[:target] = target if target
    opts[:integration] = integration if integration
    Evilution::Config.new(**opts)
  end

  def tests(files:, spec:, integration:, skip_config:)
    opts = { target_files: files }
    opts[:skip_config_file] = true if skip_config
    opts[:spec_files] = spec if spec
    opts[:integration] = integration if integration
    Evilution::Config.new(**opts)
  end
end
