# frozen_string_literal: true

require "evilution/runner/mutation_executor/infra_retry"

RSpec.describe Evilution::Runner::MutationExecutor::InfraRetry do
  subject(:retry_pass) { described_class.new(runner: runner, pipeline: pipeline) }

  let(:runner) { instance_double(Evilution::Runner::MutationExecutor::MutationRunner) }
  let(:pipeline) { instance_double(Evilution::Runner::MutationExecutor::NeutralizationPipeline) }
  let(:integration) { instance_double(Evilution::Integration::RSpec) }

  def mutation(name)
    instance_double(Evilution::Mutation, name.to_s, strip_sources!: nil)
  end

  def result(status, mutation, error_class: nil)
    Evilution::Result::MutationResult.new(
      mutation: mutation,
      status: status,
      duration: 0.01,
      error: error_class ? Evilution::Result::ErrorInfo.new(klass: error_class, message: "boom") : nil
    )
  end

  def infra_neutral(mutation)
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: :neutral, duration: 0.01,
      error: Evilution::Result::ErrorInfo.new(klass: "Timeout::Error", message: "execution expired")
    )
  end

  it "has re-run nothing before it is called" do
    expect(retry_pass.retried_count).to eq(0)
  end

  describe "#call" do
    let(:contended) { mutation(:contended) }
    let(:clean) { mutation(:clean) }

    it "counts each call on its own" do
      allow(runner).to receive(:call) { |m, **| result(:killed, m) }
      allow(pipeline).to receive(:call) { |r, **| r }
      retry_pass.call([infra_neutral(contended)], baseline_result: nil, integration: integration)

      retry_pass.call([result(:killed, clean)], baseline_result: nil, integration: integration)

      expect(retry_pass.retried_count).to eq(0)
    end

    # The executor hands over the results of the parallel pass; replacing
    # entries in place would edit an array it still holds.
    it "returns a new array rather than editing the one it was given" do
      results = [infra_neutral(contended)].freeze
      rerun = result(:killed, contended)
      allow(runner).to receive(:call).and_return(rerun)
      allow(pipeline).to receive(:call).and_return(rerun)

      expect(retry_pass.call(results, baseline_result: nil, integration: integration)).to eq([rerun])
    end

    it "re-runs the infra-neutralised mutations and keeps the new verdict" do
      results = [result(:killed, clean), infra_neutral(contended)]
      rerun = result(:survived, contended)
      allow(runner).to receive(:call).with(contended, integration: integration).and_return(rerun)
      allow(pipeline).to receive(:call).with(rerun, baseline_result: nil).and_return(rerun)

      expect(retry_pass.call(results, baseline_result: nil, integration: integration))
        .to eq([results.first, rerun])
    end

    it "reports how many it re-ran" do
      results = [infra_neutral(contended), infra_neutral(clean)]
      allow(runner).to receive(:call) { |m, **| result(:killed, m) }
      allow(pipeline).to receive(:call) { |r, **| r }

      retry_pass.call(results, baseline_result: nil, integration: integration)

      expect(retry_pass.retried_count).to eq(2)
    end

    it "leaves results alone when nothing was neutralised by infrastructure" do
      results = [result(:killed, clean), result(:survived, contended)]
      allow(runner).to receive(:call)

      expect(retry_pass.call(results, baseline_result: nil, integration: integration)).to eq(results)
      expect(runner).not_to have_received(:call)
    end

    # A neutral from a failing baseline is a real verdict about the spec, not a
    # missed one, so re-running it would change nothing.
    it "does not re-run a neutral that carries no infra error" do
      results = [result(:neutral, contended)]
      allow(runner).to receive(:call)

      expect(retry_pass.call(results, baseline_result: nil, integration: integration)).to eq(results)
      expect(runner).not_to have_received(:call)
    end

    it "releases the sources it held for the retry" do
      results = [infra_neutral(contended)]
      rerun = result(:killed, contended)
      allow(runner).to receive(:call).and_return(rerun)
      allow(pipeline).to receive(:call).and_return(rerun)

      retry_pass.call(results, baseline_result: nil, integration: integration)

      expect(contended).to have_received(:strip_sources!)
    end

    it "passes the baseline result through to the pipeline" do
      baseline = double("BaselineResult", failed?: true)
      results = [infra_neutral(contended)]
      rerun = result(:killed, contended)
      allow(runner).to receive(:call).and_return(rerun)
      allow(pipeline).to receive(:call).with(rerun, baseline_result: baseline).and_return(rerun)

      retry_pass.call(results, baseline_result: baseline, integration: integration)

      expect(pipeline).to have_received(:call).with(rerun, baseline_result: baseline)
    end
  end
end
