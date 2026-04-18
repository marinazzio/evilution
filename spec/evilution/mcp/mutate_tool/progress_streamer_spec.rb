# frozen_string_literal: true

require "evilution/mcp/mutate_tool"

RSpec.describe Evilution::MCP::MutateTool::ProgressStreamer do
  describe ".build" do
    it "returns nil when suggest_tests is false" do
      ctx = double(report_progress: nil)
      expect(described_class.build(server_context: ctx, suggest_tests: false, integration: :rspec)).to be_nil
    end

    it "returns nil when server_context does not support report_progress" do
      ctx = Object.new
      expect(described_class.build(server_context: ctx, suggest_tests: true, integration: :rspec)).to be_nil
    end

    it "returns a callable that skips non-survived results" do
      ctx = double
      allow(ctx).to receive(:respond_to?).with(:report_progress).and_return(true)
      allow(ctx).to receive(:report_progress)
      callback = described_class.build(server_context: ctx, suggest_tests: true, integration: :rspec)

      callback.call(double(survived?: false))
      expect(ctx).not_to have_received(:report_progress)
    end

    it "reports progress for survived results" do
      ctx = double
      allow(ctx).to receive(:respond_to?).with(:report_progress).and_return(true)
      allow(ctx).to receive(:report_progress)
      callback = described_class.build(server_context: ctx, suggest_tests: true, integration: :rspec)

      mutation = double(
        subject: double(name: "Foo#bar"),
        file_path: "lib/foo.rb",
        line: 5,
        operator_name: "op",
        diff: "diff"
      )
      allow_any_instance_of(Evilution::Reporter::Suggestion).to receive(:suggestion_for).and_return("sugg")

      callback.call(double(survived?: true, mutation: mutation))
      expect(ctx).to have_received(:report_progress).with(1, message: kind_of(String))
    end

    it "swallows errors raised inside the callback" do
      ctx = double
      allow(ctx).to receive(:respond_to?).with(:report_progress).and_return(true)
      allow(ctx).to receive(:report_progress).and_raise(RuntimeError, "boom")
      callback = described_class.build(server_context: ctx, suggest_tests: true, integration: :rspec)

      mutation = double(
        subject: double(name: "Foo#bar"),
        file_path: "lib/foo.rb",
        line: 5,
        operator_name: "op",
        diff: "diff"
      )
      allow_any_instance_of(Evilution::Reporter::Suggestion).to receive(:suggestion_for).and_return("sugg")

      expect { callback.call(double(survived?: true, mutation: mutation)) }.not_to raise_error
    end
  end
end
