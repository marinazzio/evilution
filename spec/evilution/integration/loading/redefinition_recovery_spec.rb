# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/integration/loading/redefinition_recovery"

RSpec.describe Evilution::Integration::Loading::RedefinitionRecovery do
  subject(:recovery) { described_class.new(constant_names: constant_names) }

  # Fake constant-names collaborator: records the source it was called with
  # and returns a fixed list of fully-qualified constant names.
  fake_class = Class.new do
    attr_accessor :names
    attr_reader :received

    def initialize
      @names = []
      @received = []
    end

    def call(source)
      @received << source
      @names
    end
  end

  let(:constant_names) { fake_class.new }

  describe "#initialize" do
    it "defaults to a real ConstantNames instance" do
      default = described_class.new
      collaborator = default.instance_variable_get(:@constant_names)

      expect(collaborator).to be_an_instance_of(Evilution::AST::ConstantNames)
    end

    it "stores the injected collaborator" do
      expect(recovery.instance_variable_get(:@constant_names))
        .to be(constant_names)
    end
  end

  describe "#call" do
    it "invokes the block and returns its value when nothing is raised" do
      result = recovery.call("source") { 42 }

      expect(result).to eq(42)
    end

    it "calls the block exactly once on the happy path" do
      calls = 0
      recovery.call("source") { calls += 1 }

      expect(calls).to eq(1)
    end

    it "re-raises an ArgumentError that is neither a redefinition " \
       "conflict nor an idempotency violation" do
      expect do
        recovery.call("source") { raise ArgumentError, "totally unrelated" }
      end.to raise_error(ArgumentError, "totally unrelated")
    end

    context "when the block raises an 'already defined' ArgumentError" do
      it "strips declared constants and retries the block once" do
        constant_names.names = ["Foo::Bar"]
        attempts = 0

        recovery.call("the source") do
          attempts += 1
          raise ArgumentError, "Foo is already defined" if attempts == 1

          :recovered
        end

        expect(attempts).to eq(2)
      end

      it "returns the retried block's value" do
        attempts = 0
        result = recovery.call("the source") do
          attempts += 1
          raise ArgumentError, "already defined" if attempts == 1

          :recovered
        end

        expect(result).to eq(:recovered)
      end

      it "removes the declared constants before retrying" do
        Object.const_set(:EvilRedefTarget, Module.new)
        constant_names.names = ["EvilRedefTarget"]
        attempts = 0

        recovery.call("the source") do
          attempts += 1
          raise ArgumentError, "already defined" if attempts == 1
        end

        expect(Object.const_defined?(:EvilRedefTarget, false)).to be(false)
      ensure
        Object.send(:remove_const, :EvilRedefTarget) if Object.const_defined?(:EvilRedefTarget, false)
      end

      it "passes the original source to the constant-name collaborator" do
        attempts = 0
        recovery.call("decl source") do
          attempts += 1
          raise ArgumentError, "already defined" if attempts == 1
        end

        expect(constant_names.received).to include("decl source")
      end

      it "propagates an error raised by the retried block" do
        attempts = 0

        expect do
          recovery.call("the source") do
            attempts += 1
            raise ArgumentError, "already defined" if attempts == 1

            raise "retry blew up"
          end
        end.to raise_error("retry blew up")
      end
    end

    context "when the block raises an idempotency-violation ArgumentError" do
      Evilution::Integration::Loading::RedefinitionRecovery::IDEMPOTENCY_PATTERNS
        .each do |pattern|
        it "swallows the #{pattern.inspect} violation and returns nil" do
          result = recovery.call("source") do
            raise ArgumentError, "thing #{pattern} here"
          end

          expect(result).to be_nil
        end
      end

      it "does not retry the block" do
        attempts = 0

        recovery.call("source") do
          attempts += 1
          raise ArgumentError, "already registered"
        end

        expect(attempts).to eq(1)
      end

      it "emits a one-shot warning naming the swallowed error" do
        expect do
          recovery.call("source") do
            raise ArgumentError, "already registered"
          end
        end.to output(
          /\[evilution\] swallowed idempotency violation on re-eval: /
        ).to_stderr
      end

      it "includes the error class and message in the warning" do
        expect do
          recovery.call("source") do
            raise ArgumentError, "already registered"
          end
        end.to output(/ArgumentError: already registered\./).to_stderr
      end

      it "warns only once for the same message across repeated calls" do
        warn_block = lambda do
          recovery.call("source") do
            raise ArgumentError, "already registered"
          end
        end

        expect do
          warn_block.call
          warn_block.call
        end.to output(
          a_string_matching(/\[evilution\]/)
            .and(satisfy { |s| s.scan("[evilution]").length == 1 })
        ).to_stderr
      end

      it "warns again for a different idempotency message" do
        expect do
          recovery.call("source") { raise ArgumentError, "already registered" }
          recovery.call("source") { raise ArgumentError, "already initialized" }
        end.to output(
          satisfy { |s| s.scan("[evilution]").length == 2 }
        ).to_stderr
      end
    end

    context "when the block raises a superclass-mismatch TypeError" do
      it "strips declared constants and retries the block once" do
        constant_names.names = ["Foo"]
        attempts = 0

        recovery.call("the source") do
          attempts += 1
          raise TypeError, "superclass mismatch for class Foo" if attempts == 1

          :recovered
        end

        expect(attempts).to eq(2)
      end

      it "returns the retried block's value" do
        attempts = 0
        result = recovery.call("the source") do
          attempts += 1
          raise TypeError, "superclass mismatch" if attempts == 1

          :recovered
        end

        expect(result).to eq(:recovered)
      end

      it "removes the declared constants before retrying" do
        Object.const_set(:EvilSuperTarget, Module.new)
        constant_names.names = ["EvilSuperTarget"]
        attempts = 0

        recovery.call("the source") do
          attempts += 1
          raise TypeError, "superclass mismatch" if attempts == 1
        end

        expect(Object.const_defined?(:EvilSuperTarget, false)).to be(false)
      ensure
        Object.send(:remove_const, :EvilSuperTarget) if Object.const_defined?(:EvilSuperTarget, false)
      end

      it "re-raises a TypeError that is not a superclass mismatch" do
        expect do
          recovery.call("source") { raise TypeError, "no implicit conversion" }
        end.to raise_error(TypeError, "no implicit conversion")
      end

      it "does not recover a one-shot TypeError that is not a " \
         "superclass mismatch" do
        attempts = 0

        expect do
          recovery.call("source") do
            attempts += 1
            raise TypeError, "no implicit conversion" if attempts == 1

            :recovered
          end
        end.to raise_error(TypeError, "no implicit conversion")
        expect(attempts).to eq(1)
      end

      it "propagates a TypeError still mismatching on the retry" do
        expect do
          recovery.call("source") do
            raise TypeError, "superclass mismatch for class Foo"
          end
        end.to raise_error(TypeError, /superclass mismatch/)
      end
    end
  end

  describe "constant removal" do
    it "skips a name whose parent namespace cannot be resolved" do
      constant_names.names = ["NonExistentEvil::Whatever"]
      attempts = 0

      expect do
        recovery.call("source") do
          attempts += 1
          raise ArgumentError, "already defined" if attempts == 1
        end
      end.not_to raise_error
    end

    it "resolves a nested parent namespace and removes the leaf constant" do
      parent = Module.new
      stub_const("EvilNestParent", parent)
      parent.const_set(:Leaf, Module.new)
      constant_names.names = ["EvilNestParent::Leaf"]
      attempts = 0

      recovery.call("source") do
        attempts += 1
        raise ArgumentError, "already defined" if attempts == 1
      end

      expect(parent.const_defined?(:Leaf, false)).to be(false)
    end

    it "does not remove a constant the source does not declare" do
      stub_const("EvilUntouched", Module.new)
      constant_names.names = []
      attempts = 0

      recovery.call("source") do
        attempts += 1
        raise ArgumentError, "already defined" if attempts == 1
      end

      expect(Object.const_defined?(:EvilUntouched, false)).to be(true)
    end

    it "does not remove an autoloaded (not yet loaded) constant" do
      parent = Module.new
      stub_const("EvilAutoParent", parent)
      parent.autoload(:Pending, "/nonexistent/evil/pending")
      constant_names.names = ["EvilAutoParent::Pending"]
      attempts = 0

      recovery.call("source") do
        attempts += 1
        raise ArgumentError, "already defined" if attempts == 1
      end

      expect(parent.autoload?(:Pending)).to eq("/nonexistent/evil/pending")
    end

    it "does not resolve through an autoloaded (not yet loaded) " \
       "intermediate namespace" do
      dir = Dir.mktmpdir("evilution_autoload")
      target = File.join(dir, "evil_autoload_ns.rb")
      File.write(target, <<~RUBY)
        module EvilAutoIntermediate
          Leaf = Module.new
        end
      RUBY
      Object.autoload(:EvilAutoIntermediate, target)
      constant_names.names = ["EvilAutoIntermediate::Leaf"]
      attempts = 0

      recovery.call("source") do
        attempts += 1
        raise ArgumentError, "already defined" if attempts == 1
      end

      # The autoload guard must short-circuit before const_get fires the
      # autoload — the autoload registration stays pending (unfired).
      expect(Object.autoload?(:EvilAutoIntermediate)).to eq(target)
    ensure
      Object.send(:remove_const, :EvilAutoIntermediate) if Object.const_defined?(:EvilAutoIntermediate, false)
      FileUtils.rm_rf(dir)
      $LOADED_FEATURES.delete(target)
    end

    it "does not resolve through a non-module constant in the path" do
      parent = Module.new
      stub_const("EvilStrParent", parent)
      parent.const_set(:NotAModule, "a string")
      parent.const_set(:Leaf, Module.new)
      constant_names.names = ["EvilStrParent::NotAModule::Leaf"]
      attempts = 0

      expect do
        recovery.call("source") do
          attempts += 1
          raise ArgumentError, "already defined" if attempts == 1
        end
      end.not_to raise_error
      expect(parent.const_defined?(:Leaf, false)).to be(true)
    end

    it "removes a top-level constant when the parent name is empty" do
      Object.const_set(:EvilTopLevel, Module.new)
      constant_names.names = ["EvilTopLevel"]
      attempts = 0

      recovery.call("source") do
        attempts += 1
        raise ArgumentError, "already defined" if attempts == 1
      end

      expect(Object.const_defined?(:EvilTopLevel, false)).to be(false)
    ensure
      Object.send(:remove_const, :EvilTopLevel) if Object.const_defined?(:EvilTopLevel, false)
    end

    it "removes nested constants in reverse (innermost first) order" do
      outer = Module.new
      Object.const_set(:EvilOrder, outer)
      outer.const_set(:Inner, Module.new)
      constant_names.names = ["EvilOrder", "EvilOrder::Inner"]
      attempts = 0

      expect do
        recovery.call("source") do
          attempts += 1
          raise ArgumentError, "already defined" if attempts == 1
        end
      end.not_to raise_error
      expect(Object.const_defined?(:EvilOrder, false)).to be(false)
    ensure
      Object.send(:remove_const, :EvilOrder) if Object.const_defined?(:EvilOrder, false)
    end
  end
end
