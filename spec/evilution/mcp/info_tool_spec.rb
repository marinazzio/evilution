# frozen_string_literal: true

require "json"
require "evilution/mcp/info_tool"
require "evilution/version"
require "evilution/feedback"

RSpec.describe Evilution::MCP::InfoTool do
  def call(**params)
    described_class.call(server_context: nil, **params)
  end

  def parse_response(response)
    JSON.parse(response.content.first[:text])
  end

  describe "class DSL" do
    it "is registered under the evilution-info tool name" do
      expect(described_class.name_value).to eq("evilution-info")
    end

    it "description includes the discovery-summary phrase" do
      expect(described_class.description).to include("Discover what evilution sees")
    end

    it "input_schema action enum matches VALID_ACTIONS" do
      enum = described_class.input_schema.to_h.dig(:properties, :action, :enum)
      expect(enum).to eq(described_class::VALID_ACTIONS)
    end
  end

  describe "VALID_ACTIONS" do
    it "lists the five supported actions" do
      expect(described_class::VALID_ACTIONS).to eq(%w[subjects tests environment statuses feedback])
    end

    it "is frozen" do
      expect(described_class::VALID_ACTIONS).to be_frozen
    end

    it "matches the dispatch ACTIONS table keys" do
      actions = described_class.send(:const_get, :ACTIONS)
      expect(actions.keys).to eq(described_class::VALID_ACTIONS)
    end
  end

  describe "action validation" do
    it "returns a config_error when action is missing" do
      response = call

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("action is required")
    end

    it "returns a real MCP response object when action is missing" do
      response = call

      # Kills return_value_removal (`return` => nil) and method_call_removal
      # (`return ResponseFormatter` => the bare module) on the action guard.
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.content.first[:text]).to be_a(String)
    end

    it "returns a config_error when action is unknown" do
      response = call(action: "nope")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("unknown action: nope")
    end

    it "returns a real MCP error response when action is unknown" do
      response = call(action: "nope")

      # Kills return_value_removal and method_call_removal on the
      # unknown-action guard: a bare `return` or `return ResponseFormatter`
      # would not yield a Response carrying the structured error payload.
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.content.first[:text]).to include("unknown action: nope")
    end

    it "does not short-circuit a valid action through the guard clauses" do
      # Kills method_body_replacement (whole body => nil / self): a known
      # action must flow past both guards and yield its real success payload.
      response = call(action: "statuses")

      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
      data = parse_response(response)
      expect(data).to have_key("statuses")
      expect(data["statuses"]).to be_an(Array)
    end
  end

  describe "dispatch routing" do
    {
      "subjects" => Evilution::MCP::InfoTool::Actions::Subjects,
      "tests" => Evilution::MCP::InfoTool::Actions::Tests,
      "environment" => Evilution::MCP::InfoTool::Actions::Environment,
      "statuses" => Evilution::MCP::InfoTool::Actions::Statuses,
      "feedback" => Evilution::MCP::InfoTool::Actions::Feedback
    }.each do |action, klass|
      it "routes action '#{action}' to #{klass}" do
        expect(klass).to receive(:call)
        call(action: action, files: ["lib/foo.rb"])
      end
    end

    it "returns the value produced by the dispatched action" do
      sentinel = Object.new
      allow(Evilution::MCP::InfoTool::Actions::Statuses).to receive(:call).and_return(sentinel)

      # Kills statement_deletion / method_call_removal / method_body_replacement
      # on the final dispatch line: if the `ACTIONS[action].call(...)` result is
      # dropped, swapped for `ACTIONS[action]`, or the body returns nil/self,
      # `call` would not hand back the action's own return value.
      expect(call(action: "statuses")).to be(sentinel)
    end

    it "invokes the dispatched action exactly once with the full keyword set" do
      received = nil
      allow(Evilution::MCP::InfoTool::Actions::Environment).to receive(:call) do |**kwargs|
        received = kwargs
      end

      call(action: "environment", target: "Foo#bar", spec: ["spec/foo_spec.rb"],
           integration: "rspec", skip_config: true)

      # Kills method_call_removal `ACTIONS[action].call` => `ACTIONS.call`:
      # the action class itself must receive :call with every forwarded kwarg.
      expect(received).to eq(
        files: nil, line_ranges: nil, target: "Foo#bar", spec: ["spec/foo_spec.rb"],
        integration: "rspec", skip_config: true
      )
    end

    # Surfaces the test-unit integration in the schema description so MCP
    # clients see it as a valid value alongside rspec and minitest.
    it "advertises test-unit in the integration param description" do
      schema = described_class.input_schema.to_h

      expect(schema[:properties][:integration][:description]).to include("test-unit")
    end

    # Kills EV-t1qg / GH #1192 nil_replacement on the kwarg defaults
    # (`target: nil` / `spec: nil` / `integration: nil` / `skip_config: nil`
    # mutated to `true`/`false`/`0`/`""`). Omitted kwargs must propagate
    # as nil into the action so downstream `if target` / `||` checks behave
    # consistently with how the CLI defaults them.
    it "forwards nil for every optional kwarg the caller did not supply" do
      received = nil
      allow(Evilution::MCP::InfoTool::Actions::Environment).to receive(:call) do |**kwargs|
        received = kwargs
      end

      call(action: "environment")

      expect(received[:target]).to be_nil
      expect(received[:spec]).to be_nil
      expect(received[:integration]).to be_nil
      expect(received[:skip_config]).to be_nil
    end
  end

  describe "parse_files invocation" do
    it "invokes RequestParser.parse_files with the raw files array" do
      allow(Evilution::MCP::InfoTool::Actions::Subjects).to receive(:call)
      expect(Evilution::MCP::InfoTool::RequestParser).to receive(:parse_files)
        .with(["lib/foo.rb"])
        .and_return(Evilution::MCP::InfoTool::RequestParser::ParsedPaths.new(files: ["lib/foo.rb"], ranges: {}))
      call(action: "subjects", files: ["lib/foo.rb"])
    end

    it "skips RequestParser.parse_files when files is absent" do
      allow(Evilution::MCP::InfoTool::Actions::Subjects).to receive(:call)
      expect(Evilution::MCP::InfoTool::RequestParser).not_to receive(:parse_files)
      call(action: "environment")
    end

    it "forwards parsed files and line ranges from parse_files into the action" do
      ranges = { "lib/foo.rb" => (10..20) }
      parsed = Evilution::MCP::InfoTool::RequestParser::ParsedPaths.new(
        files: ["lib/foo.rb"], ranges: ranges
      )
      allow(Evilution::MCP::InfoTool::RequestParser).to receive(:parse_files).and_return(parsed)

      received = nil
      allow(Evilution::MCP::InfoTool::Actions::Subjects).to receive(:call) do |**kwargs|
        received = kwargs
      end

      call(action: "subjects", files: ["lib/foo.rb:10-20"])

      # Kills statement_deletion / method_call_removal across lines 79-84:
      # `parsed_files = nil`, `line_ranges = nil`, the whole `if files` block,
      # `parsed = RequestParser.parse_files(...)`, `parsed_files = parsed.files`,
      # and `line_ranges = parsed.ranges` must all run so the action sees the
      # actual parsed values rather than nil or the ParsedPaths object itself.
      expect(received[:files]).to eq(["lib/foo.rb"])
      expect(received[:line_ranges]).to eq(ranges)
    end

    it "passes nil files and line ranges to the action when files is absent" do
      received = nil
      allow(Evilution::MCP::InfoTool::Actions::Environment).to receive(:call) do |**kwargs|
        received = kwargs
      end

      call(action: "environment")

      # Kills statement_deletion of `parsed_files = nil` / `line_ranges = nil`:
      # without those initializers the locals would be undefined for the
      # files-absent path and the dispatch call would raise.
      expect(received[:files]).to be_nil
      expect(received[:line_ranges]).to be_nil
    end
  end

  describe "rescue orchestration" do
    it "maps Evilution::ConfigError raised by the action to a config_error response" do
      allow(Evilution::MCP::InfoTool::Actions::Environment).to receive(:call)
        .and_raise(Evilution::ConfigError.new("boom"))

      response = call(action: "environment")

      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("config_error")
      expect(data["error"]["message"]).to eq("boom")
    end

    it "maps a generic Evilution::Error raised by the action to a runtime_error response" do
      allow(Evilution::MCP::InfoTool::Actions::Statuses).to receive(:call)
        .and_raise(Evilution::Error.new("kaboom"))

      response = call(action: "statuses")

      # Kills method_call_removal `ResponseFormatter.error_for(e)` => `ResponseFormatter`:
      # the rescue must actually build an error Response from the exception.
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be true
      data = parse_response(response)
      expect(data["error"]["type"]).to eq("runtime_error")
      expect(data["error"]["message"]).to eq("kaboom")
    end
  end

  describe "end-to-end action payloads" do
    it "returns the status glossary for the 'statuses' action" do
      data = parse_response(call(action: "statuses"))

      expect(data["statuses"].map { |s| s["status"] })
        .to include("killed", "survived", "error", "neutral")
    end

    it "returns version and settings for the 'environment' action" do
      data = parse_response(call(action: "environment"))

      expect(data["version"]).to eq(Evilution::VERSION)
      expect(data["ruby"]).to eq(RUBY_VERSION)
      expect(data["settings"]).to be_a(Hash)
    end

    it "returns the discussion URL for the 'feedback' action" do
      data = parse_response(call(action: "feedback"))

      expect(data["discussion_url"]).to eq(Evilution::Feedback::DISCUSSION_URL)
      expect(data["version"]).to eq(Evilution::VERSION)
    end
  end
end

RSpec.describe Evilution::MCP::InfoTool, "feedback action registration" do
  it "lists feedback in VALID_ACTIONS" do
    expect(described_class::VALID_ACTIONS).to include("feedback")
  end

  it "dispatches action='feedback' to Actions::Feedback" do
    response = described_class.call(server_context: nil, action: "feedback")
    body = JSON.parse(response.content.first[:text])
    expect(body["discussion_url"]).to eq(Evilution::Feedback::DISCUSSION_URL)
  end
end
