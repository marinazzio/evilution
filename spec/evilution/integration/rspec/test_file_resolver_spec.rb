# frozen_string_literal: true

require "spec_helper"
require "evilution/integration/rspec/test_file_resolver"
require "evilution/integration/rspec/unresolved_spec_warner"

RSpec.describe Evilution::Integration::RSpec::TestFileResolver do
  let(:mutation) { instance_double("Mutation", file_path: "lib/foo.rb") }
  let(:warner) { instance_double(Evilution::Integration::RSpec::UnresolvedSpecWarner, call: nil) }
  let(:related_heuristic) { instance_double("RelatedSpecHeuristic", call: []) }

  def build(spec_selector_result:, **overrides)
    spec_selector = ->(_path) { spec_selector_result }
    described_class.new(
      test_files: nil,
      spec_selector: spec_selector,
      related_spec_heuristic: related_heuristic,
      related_specs_heuristic_enabled: false,
      fallback_to_full_suite: false,
      warner: warner,
      **overrides
    )
  end

  it "returns test_files override and ignores spec_selector when test_files: is set" do
    resolver = build(spec_selector_result: ["wrong"], test_files: ["forced.rb"])
    expect(resolver.call(mutation)).to eq(["forced.rb"])
  end

  it "returns spec_selector results when non-empty" do
    resolver = build(spec_selector_result: ["spec/foo_spec.rb"])
    expect(resolver.call(mutation)).to eq(["spec/foo_spec.rb"])
  end

  it "returns ['spec'] when selector empty AND fallback_to_full_suite is true" do
    resolver = build(spec_selector_result: [], fallback_to_full_suite: true)
    expect(resolver.call(mutation)).to eq(["spec"])
    expect(warner).to have_received(:call).with("lib/foo.rb", fallback_to_full_suite: true)
  end

  it "returns nil when selector empty AND fallback_to_full_suite is false" do
    resolver = build(spec_selector_result: [], fallback_to_full_suite: false)
    expect(resolver.call(mutation)).to be_nil
    expect(warner).to have_received(:call).with("lib/foo.rb", fallback_to_full_suite: false)
  end

  it "unions related_spec_heuristic results with selector results when heuristic enabled, deduped" do
    allow(related_heuristic).to receive(:call).with(mutation).and_return(["spec/related_spec.rb", "spec/foo_spec.rb"])
    resolver = build(spec_selector_result: ["spec/foo_spec.rb"], related_specs_heuristic_enabled: true)
    expect(resolver.call(mutation)).to eq(["spec/foo_spec.rb", "spec/related_spec.rb"])
  end

  it "skips related_spec_heuristic when not enabled" do
    resolver = build(spec_selector_result: ["spec/foo_spec.rb"], related_specs_heuristic_enabled: false)
    resolver.call(mutation)
    expect(related_heuristic).not_to have_received(:call)
  end
end
