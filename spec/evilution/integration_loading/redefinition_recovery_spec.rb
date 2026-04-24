# frozen_string_literal: true

require "evilution/integration/loading/redefinition_recovery"

RSpec.describe Evilution::Integration::Loading::RedefinitionRecovery do
  subject(:recovery) { described_class.new }

  let(:source) { "class EvilutionRecoveryTest; end\n" }

  after do
    Object.send(:remove_const, :EvilutionRecoveryTest) if defined?(EvilutionRecoveryTest)
    Object.send(:remove_const, :EvilutionRecoveryOuter) if defined?(EvilutionRecoveryOuter)
  end

  describe "#call" do
    it "yields once when the block succeeds" do
      calls = 0
      recovery.call(source) { calls += 1 }

      expect(calls).to eq(1)
    end

    it "returns the block's value on success" do
      expect(recovery.call(source) { :ok }).to eq(:ok)
    end

    it "re-raises ArgumentError whose message does not mention redefinition" do
      expect { recovery.call(source) { raise ArgumentError, "other issue" } }
        .to raise_error(ArgumentError, "other issue")
    end

    it "strips redeclared constants and retries when block raises 'already defined'" do
      Object.const_set(:EvilutionRecoveryTest, Class.new)

      attempts = 0
      recovery.call(source) do
        attempts += 1
        raise ArgumentError, "foo is already defined on EvilutionRecoveryTest" if attempts == 1
      end

      expect(attempts).to eq(2)
      expect(defined?(EvilutionRecoveryTest)).to be_nil
    end

    it "re-raises a persistent conflict on the second attempt" do
      Object.const_set(:EvilutionRecoveryTest, Class.new)

      expect do
        recovery.call(source) do
          raise ArgumentError, "foo is already defined on EvilutionRecoveryTest"
        end
      end.to raise_error(ArgumentError, /already defined/)
    end

    it "does not remove autoloaded constants" do
      parent = Module.new
      Object.const_set(:EvilutionRecoveryOuter, parent)
      parent.autoload(:Inner, "/nonexistent/path.rb")

      nested_source = "class EvilutionRecoveryOuter::Inner; end\n"
      attempts = 0
      expect do
        recovery.call(nested_source) do
          attempts += 1
          raise ArgumentError, "thing is already defined"
        end
      end.to raise_error(ArgumentError)

      expect(parent.autoload?(:Inner)).to eq("/nonexistent/path.rb")
    end
  end
end
