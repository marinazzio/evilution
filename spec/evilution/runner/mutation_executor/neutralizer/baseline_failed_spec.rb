# frozen_string_literal: true

require "evilution/config"
require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/neutralizer/baseline_failed"

RSpec.describe Evilution::Runner::MutationExecutor::Neutralizer::BaselineFailed do
  def mutation(file: "lib/foo.rb")
    instance_double(Evilution::Mutation, file_path: file)
  end

  def survived(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :survived, duration: 0.01)
  end

  def killed(mut)
    Evilution::Result::MutationResult.new(mutation: mut, status: :killed, duration: 0.01)
  end

  def baseline_failed(failed_files: [])
    instance_double("BaselineResult", failed?: true, failed_spec_files: failed_files)
  end

  def neutralizer(spec_files: [], spec_resolver: ->(_f) { "spec/foo_spec.rb" }, fallback_dir: "spec")
    cfg = Evilution::Config.new(quiet: true, baseline: false, skip_config_file: true, spec_files: spec_files)
    described_class.new(config: cfg, spec_resolver: spec_resolver, fallback_dir: fallback_dir)
  end

  it "returns the result unchanged when result is not survived" do
    r = killed(mutation)
    expect(neutralizer.call(r, baseline_result: baseline_failed)).to be(r)
  end

  it "returns the result unchanged when baseline_result is nil" do
    r = survived(mutation)
    expect(neutralizer.call(r, baseline_result: nil)).to be(r)
  end

  it "returns the result unchanged when baseline did not fail" do
    r = survived(mutation)
    baseline_ok = instance_double("BaselineResult", failed?: false)
    expect(neutralizer.call(r, baseline_result: baseline_ok)).to be(r)
  end

  it "neutralizes survived results unconditionally when config.spec_files is non-empty" do
    nz = neutralizer(spec_files: ["spec/foo_spec.rb"])
    r = survived(mutation)
    out = nz.call(r, baseline_result: baseline_failed)
    expect(out.status).to eq(:neutral)
  end

  it "neutralizes when resolved spec_file is in baseline.failed_spec_files" do
    resolver = ->(_f) { "spec/foo_spec.rb" }
    nz = neutralizer(spec_resolver: resolver)
    r = survived(mutation)
    bl = baseline_failed(failed_files: ["spec/foo_spec.rb"])
    expect(nz.call(r, baseline_result: bl).status).to eq(:neutral)
  end

  it "does NOT neutralize when resolved spec_file is not in baseline.failed_spec_files" do
    resolver = ->(_f) { "spec/foo_spec.rb" }
    nz = neutralizer(spec_resolver: resolver)
    r = survived(mutation)
    bl = baseline_failed(failed_files: ["spec/other_spec.rb"])
    expect(nz.call(r, baseline_result: bl)).to be(r)
  end

  it "uses fallback_dir when spec_resolver returns nil" do
    resolver = ->(_f) {}
    nz = neutralizer(spec_resolver: resolver, fallback_dir: "spec")
    r = survived(mutation)
    bl = baseline_failed(failed_files: ["spec"])
    expect(nz.call(r, baseline_result: bl).status).to eq(:neutral)
  end
end
