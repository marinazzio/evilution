# frozen_string_literal: true

require "evilution/integration/loading/concern_registry"

RSpec.describe Evilution::Integration::Loading::ConcernRegistry do
  subject(:registry) { described_class.new }

  # Stands in for ActiveSupport::Concern: a module others extend themselves
  # with, which has an `extended` hook of its own.
  let(:concern) do
    Module.new do
      def self.extended(base)
        base.instance_variable_set(:@_dependencies, [])
      end
    end
  end

  def concern_module(extending = concern)
    Module.new.tap { |mod| mod.extend(extending) }
  end

  describe "#concerns" do
    it "lists a module extended with the concern before the first call" do
      existing = concern_module

      expect(registry.concerns(concern)).to include(existing)
    end

    it "lists a module extended with the concern after the first call" do
      registry.concerns(concern)
      later = concern_module

      expect(registry.concerns(concern)).to include(later)
    end

    it "leaves modules that are not extended with the concern out" do
      plain = Module.new
      concern_module

      expect(registry.concerns(concern)).not_to include(plain)
    end

    it "still runs the concern's own extended hook" do
      registry.concerns(concern)

      expect(concern_module.instance_variable_get(:@_dependencies)).to eq([])
    end

    it "lists each module once" do
      existing = concern_module
      registry.concerns(concern)
      existing.extend(concern)

      expect(registry.concerns(concern).count { |mod| mod.equal?(existing) }).to eq(1)
    end

    # The heap is walked for the modules that existed before the registry
    # looked; the ones that come later announce themselves. Walking it on
    # every evaluation touched every object, in a forked mutation process
    # every page shared with the parent.
    it "walks the heap once, however often it is asked" do
      allow(ObjectSpace).to receive(:each_object).and_call_original

      registry.concerns(concern)
      concern_module
      registry.concerns(concern)
      registry.concerns(concern)

      expect(ObjectSpace).to have_received(:each_object).once
    end

    it "starts over for another concern module" do
      concern_module(concern)
      registry.concerns(concern)
      other = Module.new
      existing = concern_module(other)

      expect(registry.concerns(other)).to eq([existing])
    end

    it "does not list a module extended with a concern module it no longer tracks" do
      registry.concerns(concern)
      other = Module.new
      registry.concerns(other)
      concern_module(concern)

      expect(registry.concerns(other)).to eq([])
    end

    it "does not send messages to the modules it walks" do
      touched = []
      proxy_class = Class.new(Module) do
        instance_methods.each { |m| undef_method(m) unless /^__|^object_id$/.match?(m) }

        define_method(:method_missing) do |name, *_args|
          touched << name
          raise "deprecated constant touched via ##{name}"
        end
      end
      proxy = proxy_class.new

      expect { registry.concerns(concern) }.not_to raise_error
      expect(touched).to eq([])
      expect(proxy.__id__).to be_an(Integer) # keeps the proxy alive across the walk
    end
  end

  describe ".default" do
    it "is one registry for the process" do
      expect(described_class.default).to be_a(described_class)
      expect(described_class.default).to be(described_class.default)
    end
  end
end
