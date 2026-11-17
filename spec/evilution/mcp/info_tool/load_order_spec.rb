# frozen_string_literal: true

require_relative "../../../support/fresh_ruby_process"

# Each file is required first in a fresh Ruby process, so no other spec has
# loaded the tool beforehand. Every action file requires the tool for its
# namespace, so the tool must finish loading before the action that started
# the chain has defined its class.
RSpec.describe "Evilution::MCP::InfoTool load order" do
  include FreshRubyProcess

  {
    "evilution/mcp/info_tool" => "Evilution::MCP::InfoTool",
    "evilution/mcp/info_tool/actions/subjects" => "Evilution::MCP::InfoTool::Actions::Subjects",
    "evilution/mcp/info_tool/actions/tests" => "Evilution::MCP::InfoTool::Actions::Tests",
    "evilution/mcp/info_tool/actions/environment" => "Evilution::MCP::InfoTool::Actions::Environment",
    "evilution/mcp/info_tool/actions/statuses" => "Evilution::MCP::InfoTool::Actions::Statuses",
    "evilution/mcp/info_tool/actions/feedback" => "Evilution::MCP::InfoTool::Actions::Feedback"
  }.each do |feature, constant|
    it "loads #{feature} on its own and defines #{constant}" do
      stdout, stderr, status = require_in_fresh_ruby(feature, constant)

      expect([stdout, stderr, status.success?]).to eq(["nil #{constant}", "", true])
    end
  end

  it "dispatches every action after an action file was loaded first" do
    script = <<~RUBY
      require "json"
      require "evilution/mcp/info_tool/actions/statuses"
      source = File.join(#{FreshRubyProcess::LIB_DIR.dump}, "evilution/mcp/info_tool/actions/statuses.rb")
      results = Evilution::MCP::InfoTool::VALID_ACTIONS.map do |action|
        response = Evilution::MCP::InfoTool.call(server_context: nil, action: action, files: [source], skip_config: true)
        error = JSON.parse(response.content.first[:text])["error"]
        error ? "\#{action}: \#{error}" : action
      end
      print results.join(",")
    RUBY

    stdout, stderr, status = run_in_fresh_ruby(script)

    expect([stdout, stderr, status.success?]).to eq(["subjects,tests,environment,statuses,feedback", "", true])
  end
end
