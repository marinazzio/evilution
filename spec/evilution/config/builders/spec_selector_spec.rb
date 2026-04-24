# frozen_string_literal: true

require "spec_helper"
require "evilution/config/builders/spec_selector"

RSpec.describe Evilution::Config::Builders::SpecSelector do
  describe ".call" do
    it "wires SpecSelector with a SpecResolver matching the integration" do
      selector = described_class.call(
        spec_files: ["spec/foo_spec.rb"],
        spec_mappings: {},
        spec_pattern: nil,
        integration: :rspec
      )
      expect(selector).to be_a(Evilution::SpecSelector)
    end

    it "passes all kwargs through to SpecSelector.new" do
      resolver = instance_double(Evilution::SpecResolver)
      expect(Evilution::Config::Builders::SpecResolver).to receive(:call)
        .with(integration: :minitest).and_return(resolver)
      expect(Evilution::SpecSelector).to receive(:new).with(
        spec_files: ["a"], spec_mappings: { "k" => ["v"] },
        spec_pattern: "p", spec_resolver: resolver
      )
      described_class.call(
        spec_files: ["a"], spec_mappings: { "k" => ["v"] },
        spec_pattern: "p", integration: :minitest
      )
    end
  end
end
