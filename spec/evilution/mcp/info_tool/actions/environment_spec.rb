# frozen_string_literal: true

require "spec_helper"
require "json"
require "evilution/mcp/info_tool/actions/environment"

RSpec.describe Evilution::MCP::InfoTool::Actions::Environment do
  def parse_body(response)
    JSON.parse(response.content.first[:text])
  end

  describe ".call" do
    it "returns version, ruby, config_file, settings keys" do
      response = described_class.call
      body = parse_body(response)
      expect(body).to include("version", "ruby", "config_file", "settings")
    end

    it "returns a hash of config attributes under 'settings'" do
      response = described_class.call
      settings = parse_body(response).fetch("settings")
      expect(settings.keys).to include(
        "timeout", "format", "integration", "jobs", "isolation", "baseline",
        "incremental", "fail_fast", "stop_on_kill", "killer_first", "skip_uncovered", "probe_first", "min_score",
        "suggest_tests", "save_session",
        "target", "skip_heredoc_literals", "ignore_patterns", "skip_sites"
      )
    end

    # With no timeout set, each mutation's limit follows the baseline: the
    # fixed timeout alone would misreport what a run will do.
    it "reports whether the timeout adapts, with its factor and bounds" do
      settings = parse_body(described_class.call).fetch("settings")

      expect(settings.slice("timeout", "adaptive_timeout", "timeout_factor", "timeout_floor", "timeout_ceiling"))
        .to eq("timeout" => 30, "adaptive_timeout" => true, "timeout_factor" => 10, "timeout_floor" => 10,
               "timeout_ceiling" => 60)
    end

    it "reports copy_worker_databases" do
      expect(parse_body(described_class.call).fetch("settings")["copy_worker_databases"]).to be(true)
    end

    it "returns current Evilution::VERSION" do
      expect(parse_body(described_class.call)["version"]).to eq(Evilution::VERSION)
    end

    it "returns the current Ruby version" do
      expect(parse_body(described_class.call)["ruby"]).to eq(RUBY_VERSION)
    end

    it "ignores unknown kwargs via **" do
      expect { described_class.call(files: ["x.rb"], target: "Foo") }.not_to raise_error
    end
  end
end
