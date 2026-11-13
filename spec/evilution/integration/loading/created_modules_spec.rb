# frozen_string_literal: true

require "evilution/integration/loading/created_modules"

RSpec.describe Evilution::Integration::Loading::CreatedModules do
  describe ".into" do
    it "returns the value of the block" do
      expect(described_class.into([]) { :evaluated }).to eq(:evaluated)
    end

    it "adds the modules created while the block runs" do
      created = []
      made = nil

      described_class.into(created) { made = Module.new }

      expect(created).to eq([made])
    end

    it "adds a module whose body defines methods" do
      created = []

      made = described_class.into(created) { Module.new { def defined_here = :yes } }

      expect(created).to eq([made])
      expect(made.instance_methods(false)).to eq([:defined_here])
    end

    it "leaves out modules created before or after the block" do
      created = []
      Module.new

      described_class.into(created) { nil }
      Module.new

      expect(created).to eq([])
    end

    it "adds the modules created before the block raised" do
      created = []
      made = nil

      expect do
        described_class.into(created) do
          made = Module.new
          raise ArgumentError, "load failed"
        end
      end.to raise_error(ArgumentError, "load failed")

      expect(created).to eq([made])
    end

    it "adds a module whose own body raised" do
      created = []

      expect do
        described_class.into(created) { Module.new { raise ArgumentError, "body failed" } }
      end.to raise_error(ArgumentError, "body failed")

      expect(created.size).to eq(1)
    end

    it "stops adding once the block has raised" do
      created = []
      begin
        described_class.into(created) { raise ArgumentError }
      rescue ArgumentError
        nil
      end
      Module.new

      expect(created).to eq([])
    end

    it "adds to every list a module is created inside of" do
      outer = []
      inner = []
      made = nil

      described_class.into(outer) { described_class.into(inner) { made = Module.new } }

      expect([outer, inner]).to eq([[made], [made]])
    end

    it "keeps adding to an outer list once an inner block is over" do
      outer = []
      inner = []
      later = nil

      described_class.into(outer) do
        described_class.into(inner) { nil }
        later = Module.new
      end

      expect([outer, inner]).to eq([[later], []])
    end

    it "adds instances of a Module subclass, for the caller to sort out" do
      created = []
      subclass = Class.new(Module)

      made = described_class.into(created) { subclass.new }

      expect(created).to eq([made])
    end

    # Seeing the modules being created is what spares a walk of the heap
    # before and after every evaluation.
    it "does not walk the heap" do
      allow(ObjectSpace).to receive(:each_object).and_call_original

      described_class.into([]) { Module.new }

      expect(ObjectSpace).not_to have_received(:each_object)
    end
  end
end
