# frozen_string_literal: true

require "evilution/integration/test_unit"

# Tests the orchestrator-level wiring of TestUnit#ensure_framework_loaded.
# The framework load itself is covered by
# spec/evilution/integration/test_unit/framework_loader_spec.rb.
RSpec.describe Evilution::Integration::TestUnit, "#ensure_framework_loaded" do
  it "fires :setup_integration_pre and :setup_integration_post hooks around framework load" do
    hooks = instance_double(Evilution::Hooks)
    allow(hooks).to receive(:fire)
    integration = described_class.new(hooks: hooks)
    framework_loader = integration.instance_variable_get(:@framework_loader)
    allow(framework_loader).to receive(:call)
    allow(framework_loader).to receive(:loaded?).and_return(false)

    integration.send(:ensure_framework_loaded)

    expect(hooks).to have_received(:fire).with(:setup_integration_pre, integration: :test_unit).ordered
    expect(hooks).to have_received(:fire).with(:setup_integration_post, integration: :test_unit).ordered
    expect(framework_loader).to have_received(:call)
  end

  it "skips firing hooks when the loader reports already-loaded" do
    hooks = instance_double(Evilution::Hooks)
    allow(hooks).to receive(:fire)
    integration = described_class.new(hooks: hooks)
    framework_loader = integration.instance_variable_get(:@framework_loader)
    allow(framework_loader).to receive(:loaded?).and_return(true)
    allow(framework_loader).to receive(:call)

    integration.send(:ensure_framework_loaded)

    expect(hooks).not_to have_received(:fire)
    expect(framework_loader).not_to have_received(:call)
  end

  it "does not fire :setup_integration_post when the loader raises" do
    hooks = instance_double(Evilution::Hooks)
    allow(hooks).to receive(:fire)
    integration = described_class.new(hooks: hooks)
    framework_loader = integration.instance_variable_get(:@framework_loader)
    allow(framework_loader).to receive(:loaded?).and_return(false)
    allow(framework_loader).to receive(:call).and_raise(Evilution::Error, "boom")

    expect { integration.send(:ensure_framework_loaded) }.to raise_error(Evilution::Error)

    expect(hooks).to have_received(:fire).with(:setup_integration_pre, integration: :test_unit)
    expect(hooks).not_to have_received(:fire).with(:setup_integration_post, integration: :test_unit)
  end
end
