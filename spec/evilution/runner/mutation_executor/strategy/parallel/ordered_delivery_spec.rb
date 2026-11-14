# frozen_string_literal: true

require "evilution/config"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/diagnostics"
require "evilution/runner/mutation_executor/result_cache"
require "evilution/runner/mutation_executor/result_packer"
require "evilution/runner/mutation_executor/result_notifier"
require "evilution/runner/mutation_executor/neutralization_pipeline"
require "evilution/runner/mutation_executor/strategy/parallel"

RSpec.describe Evilution::Runner::MutationExecutor::Strategy::Parallel::OrderedDelivery do
  let(:packer) { Evilution::Runner::MutationExecutor::ResultPacker.new }
  let(:backend) { instance_double("Cache", fetch: nil).tap { |b| allow(b).to receive(:store) } }
  let(:notifier) { instance_spy(Evilution::Runner::MutationExecutor::ResultNotifier, notify: :continue) }
  let(:diagnostics) { instance_spy(Evilution::Runner::Diagnostics) }
  let(:mutations) { Array.new(4) { |i| mutation("m#{i}") } }

  def mutation(id)
    instance_double(Evilution::Mutation, file_path: "lib/foo.rb", to_s: id, unparseable?: false, strip_sources!: nil)
  end

  def compact(status, error_class: nil)
    { status: status, duration: 0.1, error_class: error_class }
  end

  def delivery(log_every: 2, diags: diagnostics)
    described_class.new(
      mutations: mutations, packer: packer,
      cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      pipeline: Evilution::Runner::MutationExecutor::NeutralizationPipeline.new([]),
      notifier: notifier, baseline_result: nil, diagnostics: diags, log_every: log_every
    )
  end

  it "holds a result back until every earlier mutation has one" do
    subject = delivery
    subject.accept(1, compact(:killed), fresh: true)
    expect(subject.results).to be_empty

    subject.accept(0, compact(:survived), fresh: true)
    expect(subject.results.map(&:mutation)).to eq(mutations.first(2))
    expect(subject.results.map(&:status)).to eq(%i[survived killed])
  end

  it "counts the results it hands the notifier in mutation order" do
    subject = delivery
    [2, 0, 1].each { |i| subject.accept(i, compact(:killed), fresh: true) }

    expect(notifier).to have_received(:notify).with(having_attributes(mutation: mutations[0]), 1).ordered
    expect(notifier).to have_received(:notify).with(having_attributes(mutation: mutations[1]), 2).ordered
    expect(notifier).to have_received(:notify).with(having_attributes(mutation: mutations[2]), 3).ordered
  end

  it "caches only results the workers produced in this run" do
    subject = delivery
    subject.accept(0, compact(:killed), fresh: false)
    subject.accept(1, compact(:killed), fresh: true)

    expect(backend).to have_received(:store).once
    expect(backend).to have_received(:store).with(mutations[1], anything)
  end

  it "drops a mutation's sources once it is judged" do
    delivery.accept(0, compact(:killed), fresh: true)

    expect(mutations[0]).to have_received(:strip_sources!)
  end

  it "drops the sources of a mutation a crash other than an infrastructure one killed" do
    delivery.accept(0, compact(:killed, error_class: "RuntimeError"), fresh: true)

    expect(mutations[0]).to have_received(:strip_sources!)
  end

  it "keeps the sources of a mutation an infrastructure crash left unjudged" do
    delivery.accept(0, compact(:killed, error_class: "Timeout::Error"), fresh: true)

    expect(mutations[0]).not_to have_received(:strip_sources!)
  end

  it "runs each result through the pipeline before keeping it" do
    pipeline = instance_double(Evilution::Runner::MutationExecutor::NeutralizationPipeline)
    neutral = Evilution::Result::MutationResult.new(mutation: mutations[0], status: :neutral)
    allow(pipeline).to receive(:call).and_return(neutral)
    subject = described_class.new(
      mutations: mutations, packer: packer, cache: Evilution::Runner::MutationExecutor::ResultCache.new(backend),
      pipeline: pipeline, notifier: notifier, baseline_result: :baseline, diagnostics: nil, log_every: 2
    )

    subject.accept(0, compact(:killed), fresh: true)

    expect(pipeline).to have_received(:call).with(an_instance_of(Evilution::Result::MutationResult), baseline_result: :baseline)
    expect(subject.results).to eq([neutral])
  end

  it "stops at the result the notifier truncates on and ignores what comes after" do
    allow(notifier).to receive(:notify).and_return(:continue, :truncate)
    subject = delivery
    subject.accept(2, compact(:killed), fresh: true)
    subject.accept(1, compact(:survived), fresh: true)
    subject.accept(0, compact(:killed), fresh: true)
    subject.accept(3, compact(:killed), fresh: true)

    expect(subject.results.map(&:mutation)).to eq(mutations.first(2))
    expect(subject).to be_truncated
    expect(mutations[2]).not_to have_received(:strip_sources!)
  end

  it "is not truncated while the notifier lets it continue" do
    subject = delivery
    expect(subject.truncated?).to be(false)

    subject.accept(0, compact(:killed), fresh: true)
    expect(subject.truncated?).to be(false)
  end

  it "logs memory every log_every results and after the last one" do
    subject = delivery(log_every: 3)
    4.times { |i| subject.accept(i, compact(:killed), fresh: true) }

    expect(diagnostics).to have_received(:log_memory).with("after batch", "3 complete").ordered
    expect(diagnostics).to have_received(:log_memory).with("after batch", "4 complete").ordered
    expect(diagnostics).to have_received(:log_memory).twice
  end

  it "logs memory at the result that truncates the run" do
    allow(notifier).to receive(:notify).and_return(:truncate)
    delivery(log_every: 3).accept(0, compact(:survived), fresh: true)

    expect(diagnostics).to have_received(:log_memory).with("after batch", "1 complete")
  end

  it "works without diagnostics" do
    expect { delivery(log_every: 1, diags: nil).accept(0, compact(:killed), fresh: true) }.not_to raise_error
  end
end
