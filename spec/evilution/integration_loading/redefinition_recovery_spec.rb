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

    describe "idempotency violations beyond 'already defined'" do
      it "swallows ArgumentError 'is already registered' without retry" do
        attempts = 0
        result = recovery.call(source) do
          attempts += 1
          raise ArgumentError, ":maybe is already registered" if attempts == 1

          :ok
        end

        expect(attempts).to eq(1)
        expect(result).to be_nil
      end

      it "swallows ArgumentError mentioning 'already initialized' without retry" do
        attempts = 0
        recovery.call(source) do
          attempts += 1
          raise ArgumentError, "Plugin already initialized" if attempts == 1
        end

        expect(attempts).to eq(1)
      end

      it "still re-raises ArgumentError unrelated to redefinition or registration" do
        expect do
          recovery.call(source) { raise ArgumentError, "bad operand for /" }
        end.to raise_error(ArgumentError, /bad operand/)
      end
    end

    # EV-lqpn (sinatra base.rb:225): `class ExtendedRack < Struct.new(:app)`
    # raises `TypeError: superclass mismatch` on re-eval because Struct.new
    # returns a fresh anonymous Class each call, so the recorded superclass
    # differs from the existing class's superclass. Common idiomatic pattern
    # for Rack middleware shims (also Data.define, Class.new in similar
    # positions). To actually apply the mutation we must remove the existing
    # constants the source defines, then retry — same pattern used for
    # ArgumentError 'already defined'. Swallowing without retry would silently
    # leave the original class in place and report the mutation as survived
    # even though it never ran.
    describe "TypeError superclass mismatch (anonymous-parent re-eval)" do
      it "strips defined constants and retries when TypeError mentions 'superclass mismatch'" do
        Object.const_set(:EvilutionRecoveryTest, Class.new)

        attempts = 0
        recovery.call(source) do
          attempts += 1
          raise TypeError, "superclass mismatch for class EvilutionRecoveryTest" if attempts == 1
        end

        expect(attempts).to eq(2)
        expect(defined?(EvilutionRecoveryTest)).to be_nil
      end

      it "re-raises a persistent superclass mismatch on the retry attempt" do
        Object.const_set(:EvilutionRecoveryTest, Class.new)

        expect do
          recovery.call(source) do
            raise TypeError, "superclass mismatch for class EvilutionRecoveryTest"
          end
        end.to raise_error(TypeError, /superclass mismatch/)
      end

      it "re-raises TypeError whose message is not a superclass mismatch" do
        expect do
          recovery.call(source) { raise TypeError, "no implicit conversion of String into Integer" }
        end.to raise_error(TypeError, /no implicit conversion/)
      end
    end
  end
end
