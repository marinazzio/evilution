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

  describe "feedback footer suppression (Surface 1)" do
    require "evilution/feedback"

    # Summary fake covering both the friction signals (Detector reads errors/
    # unparseable/unresolved) and every method Reporter::CLI invokes when it
    # renders a real text report. Fresh name avoids collisions with structs
    # defined in other reporter specs (Summary, FrictionSummary, TrailerFrictionSummary).
    unless defined?(PublisherFrictionSummary)
      PublisherFrictionSummary = Struct.new(
        :errors, :unparseable, :unresolved,
        :results, :total, :killed, :survived, :timed_out, :neutral, :equivalent,
        :duration, :killtime, :efficiency, :mutations_per_second, :peak_memory_mb,
        :score, :score_denominator, :skipped, :disabled_mutations,
        :survived_results, :killed_results, :neutral_results, :equivalent_results,
        :unresolved_results, :unparseable_results, :coverage_gaps,
        keyword_init: true
      ) do
        def initialize(errors: 0, unparseable: 0, unresolved: 0)
          super(
            errors: errors, unparseable: unparseable, unresolved: unresolved,
            results: [], total: 0, killed: 0, survived: 0, timed_out: 0,
            neutral: 0, equivalent: 0, duration: 0.0, killtime: 0.0,
            efficiency: 0.0, mutations_per_second: 0.0, peak_memory_mb: nil,
            score: 0.0, score_denominator: 0, skipped: 0,
            disabled_mutations: [], survived_results: [], killed_results: [],
            neutral_results: [], equivalent_results: [], unresolved_results: [],
            unparseable_results: [], coverage_gaps: []
          )
        end

        def truncated?
          false
        end

        def success?(min_score:)
          score >= min_score
        end
      end
    end

    let(:friction_summary) { PublisherFrictionSummary.new(errors: 1) }

    it "does NOT emit feedback URL when format=json" do
      cfg = config(format: :json)
      expect { described_class.new(cfg).publish(friction_summary) }
        .not_to output(/#{Regexp.escape(Evilution::Feedback::DISCUSSION_URL)}/).to_stdout
    end

    it "does NOT emit feedback URL when quiet=true and format=text" do
      cfg = config(format: :text, quiet: true)
      expect { described_class.new(cfg).publish(friction_summary) }
        .not_to output(/#{Regexp.escape(Evilution::Feedback::DISCUSSION_URL)}/).to_stdout
    end

    it "does NOT emit feedback URL via stdout when format=html" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          cfg = config(format: :html)
          expect { described_class.new(cfg).publish(friction_summary) }
            .not_to output(/#{Regexp.escape(Evilution::Feedback::DISCUSSION_URL)}/).to_stdout
        end
      end
    end

    it "DOES emit feedback URL when format=text and not quiet" do
      cfg = config(format: :text)
      expect { described_class.new(cfg).publish(friction_summary) }
        .to output(/#{Regexp.escape(Evilution::Feedback::DISCUSSION_URL)}/).to_stdout
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
