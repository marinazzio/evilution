# frozen_string_literal: true

require "json"
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

    it "reports progress for survived results with a JSON payload of the mutation detail" do
      ctx = double
      allow(ctx).to receive(:respond_to?).with(:report_progress).and_return(true)
      reported = nil
      allow(ctx).to receive(:report_progress) { |_idx, message:| reported = message }
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
      payload = JSON.parse(reported)
      expect(payload).to eq(
        "operator" => "op",
        "file" => "lib/foo.rb",
        "line" => 5,
        "subject" => "Foo#bar",
        "diff" => "diff",
        "suggestion" => "sugg"
      )
    end

    it "swallows errors raised inside the callback and warns once" do
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
      result = double(survived?: true, mutation: mutation)

      expect do
        callback.call(result)
        callback.call(result)
        callback.call(result)
      end.to output(/progress stream disabled after error: RuntimeError: boom/).to_stderr

      expect(ctx).to have_received(:report_progress).once
    end

    it "warns with the error's message text, not its default to_s" do
      # An error class whose #to_s (class name) differs from its #message,
      # so the warning must interpolate e.message explicitly.
      error_class = Class.new(StandardError) do
        def message
          "the real failure reason"
        end
      end
      ctx = double
      allow(ctx).to receive(:respond_to?).with(:report_progress).and_return(true)
      allow(ctx).to receive(:report_progress).and_raise(error_class.new)
      callback = described_class.build(server_context: ctx, suggest_tests: true, integration: :rspec)

      mutation = double(
        subject: double(name: "Foo#bar"),
        file_path: "lib/foo.rb",
        line: 5,
        operator_name: "op",
        diff: "diff"
      )
      allow_any_instance_of(Evilution::Reporter::Suggestion).to receive(:suggestion_for).and_return("sugg")

      expect do
        callback.call(double(survived?: true, mutation: mutation))
      end.to output(/progress stream disabled after error: .+: the real failure reason/).to_stderr
    end
  end
end
