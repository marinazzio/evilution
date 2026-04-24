# frozen_string_literal: true

require "evilution/integration/loading/constant_pinner"

RSpec.describe Evilution::Integration::Loading::ConstantPinner do
  subject(:pinner) { described_class.new }

  describe "#call" do
    it "returns the list of constant names found in source" do
      stub_const("EvilutionPinTopLevel", Module.new)

      names = pinner.call("module EvilutionPinTopLevel; end\n")

      expect(names).to eq(["EvilutionPinTopLevel"])
    end

    it "triggers const_get on defined constants to pin them against autoload" do
      pinned_module = Module.new
      stub_const("EvilutionPinAutoload", pinned_module)

      expect(Object).to receive(:const_get).with("EvilutionPinAutoload").and_call_original

      pinner.call("module EvilutionPinAutoload; end\n")
    end

    it "skips names that are not defined on Object" do
      expect { pinner.call("module EvilutionPinUndefined_xyz; end\n") }.not_to raise_error
    end

    it "swallows NameError raised by const_get" do
      allow(Object).to receive(:const_defined?).and_return(true)
      allow(Object).to receive(:const_get).and_raise(NameError)

      expect { pinner.call("module EvilutionPinNameErr; end\n") }.not_to raise_error
    end

    it "pins nested constant names" do
      stub_const("EvilutionPinOuter", Module.new)
      stub_const("EvilutionPinOuter::Inner", Class.new)

      names = pinner.call(<<~RUBY)
        module EvilutionPinOuter
          class Inner
          end
        end
      RUBY

      expect(names).to include("EvilutionPinOuter", "EvilutionPinOuter::Inner")
    end

    it "accepts an injected constant-names extractor" do
      extractor = instance_double(Evilution::AST::ConstantNames, call: ["EvilutionPinInjected"])
      stub_const("EvilutionPinInjected", Module.new)

      pinner = described_class.new(constant_names: extractor)
      expect(extractor).to receive(:call).with("source")

      pinner.call("source")
    end
  end
end
