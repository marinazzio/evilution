# frozen_string_literal: true

require "tmpdir"
require "evilution/config"
require "evilution/runner/report_publisher"

RSpec.describe Evilution::Runner::ReportPublisher do
  def config(**overrides)
    Evilution::Config.new(quiet: false, baseline: false, skip_config_file: true, **overrides)
  end

  let(:summary) { double("Summary") }

  describe "#publish" do
    it "does nothing when no reporter matches the format" do
      cfg = Evilution::Config.allocate
      cfg.instance_variable_set(:@format, :bogus)
      cfg.instance_variable_set(:@quiet, false)
      publisher = described_class.new(cfg)
      expect { publisher.publish(summary) }.not_to output.to_stdout
    end

    it "writes text output to stdout when format is :text" do
      cfg = config(format: :text)
      reporter = instance_double(Evilution::Reporter::CLI, call: "txt-output")
      allow(Evilution::Reporter::CLI).to receive(:new).and_return(reporter)

      publisher = described_class.new(cfg)
      expect { publisher.publish(summary) }.to output("txt-output\n").to_stdout
    end

    it "writes HTML to a file when format is :html" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          cfg = config(format: :html)
          reporter = instance_double(Evilution::Reporter::HTML, call: "<html>x</html>")
          allow(Evilution::Reporter::HTML).to receive(:new).and_return(reporter)

          publisher = described_class.new(cfg)
          publisher.publish(summary)
          expect(File.read("evilution-report.html")).to eq("<html>x</html>")
        end
      end
    end

    it "suppresses stdout when config.quiet" do
      cfg = config(format: :text, quiet: true)
      reporter = instance_double(Evilution::Reporter::CLI, call: "txt")
      allow(Evilution::Reporter::CLI).to receive(:new).and_return(reporter)

      publisher = described_class.new(cfg)
      expect { publisher.publish(summary) }.not_to output.to_stdout
    end

    it "builds JSON reporter when format is :json" do
      cfg = config(format: :json, integration: :rspec)
      expect(Evilution::Reporter::JSON).to receive(:new)
        .with(integration: :rspec)
        .and_return(instance_double(Evilution::Reporter::JSON, call: "{}"))
      described_class.new(cfg).publish(summary)
    end

    it "loads baseline session for HTML reporter when configured" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          cfg = config(format: :html, baseline_session: "session.jsonl")
          store = instance_double(Evilution::Session::Store)
          allow(Evilution::Session::Store).to receive(:new).and_return(store)
          expect(store).to receive(:load).with("session.jsonl").and_return(:baseline)
          expect(Evilution::Reporter::HTML).to receive(:new)
            .with(baseline: :baseline, integration: :rspec)
            .and_return(instance_double(Evilution::Reporter::HTML, call: "<html/>"))

          described_class.new(cfg).publish(summary)
        end
      end
    end
  end

  describe "#save_session" do
    it "is a no-op when save_session is disabled" do
      publisher = described_class.new(config(save_session: false))
      expect(Evilution::Session::Store).not_to receive(:new)
      publisher.save_session(summary)
    end

    it "delegates to Session::Store when enabled" do
      publisher = described_class.new(config(save_session: true))
      store = instance_double(Evilution::Session::Store)
      expect(Evilution::Session::Store).to receive(:new).and_return(store)
      expect(store).to receive(:save).with(summary)
      publisher.save_session(summary)
    end

    it "warns when save fails and is not quiet" do
      publisher = described_class.new(config(save_session: true))
      store = instance_double(Evilution::Session::Store)
      allow(Evilution::Session::Store).to receive(:new).and_return(store)
      allow(store).to receive(:save).and_raise(StandardError, "disk full")

      expect { publisher.save_session(summary) }.to output(/failed to save session: disk full/).to_stderr
    end
  end
end
