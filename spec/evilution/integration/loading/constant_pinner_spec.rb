# frozen_string_literal: true

require "evilution/integration/loading/constant_pinner"

RSpec.describe Evilution::Integration::Loading::ConstantPinner do
  subject(:pinner) { described_class.new }

  describe "#initialize" do
    it "defaults to a real ConstantNames instance that extracts names from source" do
      stub_const("EvilutionMirrorPinDefault", Module.new)

      names = described_class.new.call("module EvilutionMirrorPinDefault; end\n")

      expect(names).to eq(["EvilutionMirrorPinDefault"])
    end

    it "stores the injected extractor so #call delegates to it" do
      extractor = instance_double(Evilution::AST::ConstantNames, call: [])
      injected = described_class.new(constant_names: extractor)

      expect(extractor).to receive(:call).with("some source").and_return([])

      injected.call("some source")
    end
  end

  describe "#call" do
    it "returns the list of constant names found in source" do
      stub_const("EvilutionMirrorPinTopLevel", Module.new)

      names = pinner.call("module EvilutionMirrorPinTopLevel; end\n")

      expect(names).to eq(["EvilutionMirrorPinTopLevel"])
    end

    it "returns the names array, not nil" do
      stub_const("EvilutionMirrorPinReturn", Module.new)

      expect(pinner.call("module EvilutionMirrorPinReturn; end\n")).not_to be_nil
    end

    it "triggers const_get on defined constants to pin them against autoload" do
      pinned_module = Module.new
      stub_const("EvilutionMirrorPinAutoload", pinned_module)

      expect(Object).to receive(:const_get).with("EvilutionMirrorPinAutoload").and_call_original

      pinner.call("module EvilutionMirrorPinAutoload; end\n")
    end

    it "does not call const_get for names that are not defined on Object" do
      expect(Object).not_to receive(:const_get)

      pinner.call("module EvilutionMirrorPinUndefined_xyz; end\n")
    end

    it "skips names that are not defined on Object without raising" do
      expect { pinner.call("module EvilutionMirrorPinUndefined_abc; end\n") }
        .not_to raise_error
    end

    it "swallows NameError raised by const_get" do
      allow(Object).to receive(:const_defined?).and_return(true)
      allow(Object).to receive(:const_get).and_raise(NameError)

      expect { pinner.call("module EvilutionMirrorPinNameErr; end\n") }
        .not_to raise_error
    end

    it "pins nested constant names" do
      stub_const("EvilutionMirrorPinOuter", Module.new)
      stub_const("EvilutionMirrorPinOuter::Inner", Class.new)

      names = pinner.call(<<~RUBY)
        module EvilutionMirrorPinOuter
          class Inner
          end
        end
      RUBY

      expect(names).to include("EvilutionMirrorPinOuter", "EvilutionMirrorPinOuter::Inner")
    end

    it "extracts names from the source argument it is given" do
      extractor = instance_double(Evilution::AST::ConstantNames)
      allow(extractor).to receive(:call).and_return([])
      injected = described_class.new(constant_names: extractor)

      injected.call("module EvilutionMirrorPinArg; end\n")

      expect(extractor).to have_received(:call).with("module EvilutionMirrorPinArg; end\n")
    end

    it "returns the names produced by the extractor" do
      extractor = instance_double(
        Evilution::AST::ConstantNames, call: ["EvilutionMirrorPinFromExtractor"]
      )
      stub_const("EvilutionMirrorPinFromExtractor", Module.new)
      injected = described_class.new(constant_names: extractor)

      expect(injected.call("source")).to eq(["EvilutionMirrorPinFromExtractor"])
    end

    it "iterates every extracted name, pinning each defined constant" do
      stub_const("EvilutionMirrorPinA", Module.new)
      stub_const("EvilutionMirrorPinB", Module.new)
      extractor = instance_double(
        Evilution::AST::ConstantNames,
        call: %w[EvilutionMirrorPinA EvilutionMirrorPinB]
      )
      injected = described_class.new(constant_names: extractor)

      expect(Object).to receive(:const_get).with("EvilutionMirrorPinA").and_call_original
      expect(Object).to receive(:const_get).with("EvilutionMirrorPinB").and_call_original

      injected.call("source")
    end
  end
end
