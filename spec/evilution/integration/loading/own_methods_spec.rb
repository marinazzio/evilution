# frozen_string_literal: true

require "evilution/integration/loading/own_methods"

RSpec.describe Evilution::Integration::Loading::OwnMethods do
  let(:file) { "/concerns/tracked.rb" }
  let(:klass) { Class.new }

  # Defines methods as written in the file at `path`: that is what tells a
  # class's own methods from those of the concern.
  def define_in(path, code, on: klass)
    on.class_eval(code, path, 1)
  end

  describe ".keeping" do
    it "returns what the block returns" do
      expect(described_class.keeping(klass, file) { :done }).to eq(:done)
    end

    it "puts back a method the file's code replaced" do
      define_in("/app/ledger.rb", "def label = :own")

      described_class.keeping(klass, file) { define_in(file, "def label = :block") }

      expect(klass.new.label).to eq(:own)
    end

    it "puts back a singleton method the file's code replaced" do
      define_in("/app/ledger.rb", "def self.level = :own")

      described_class.keeping(klass, file) { define_in(file, "def self.level = :block") }

      expect(klass.level).to eq(:own)
    end

    it "puts a method back with the visibility it had" do
      define_in("/app/ledger.rb", "private def hidden = :own\nprotected def guarded = :own\ndef open = :own")

      described_class.keeping(klass, file) { define_in(file, "def hidden = 1\ndef guarded = 2\nprivate def open = 3") }

      expect(klass.private_instance_methods(false)).to eq([:hidden])
      expect(klass.protected_instance_methods(false)).to eq([:guarded])
      expect(klass.public_instance_methods(false)).to eq([:open])
    end

    it "lets the file's code replace a method written in that file" do
      define_in(file, "def label = :first")

      described_class.keeping(klass, file) { define_in(file, "def label = :second") }

      expect(klass.new.label).to eq(:second)
    end

    it "lets the file's code add a method" do
      described_class.keeping(klass, file) { define_in(file, "def added = :block") }

      expect(klass.new.added).to eq(:block)
    end

    it "leaves alone a method replaced from somewhere else" do
      define_in("/app/ledger.rb", "def label = :own")

      described_class.keeping(klass, file) { define_in("/app/patch.rb", "def label = :patched") }

      expect(klass.new.label).to eq(:patched)
    end

    it "leaves a method the block removed removed" do
      define_in("/app/ledger.rb", "def gone = :own\nprivate def hidden = :own")

      described_class.keeping(klass, file) do
        klass.send(:remove_method, :gone)
        klass.send(:remove_method, :hidden)
      end

      expect(klass.instance_methods(false) + klass.private_instance_methods(false)).to eq([])
    end

    it "puts a private method back when it was replaced" do
      define_in("/app/ledger.rb", "private def hidden = :own")

      described_class.keeping(klass, file) { define_in(file, "private def hidden = :block") }

      expect(klass.new.send(:hidden)).to eq(:own)
    end

    it "puts the methods back when the block raises, and lets the error through" do
      define_in("/app/ledger.rb", "def label = :own")

      expect do
        described_class.keeping(klass, file) do
          define_in(file, "def label = :block")
          raise ArgumentError, "bad"
        end
      end.to raise_error(ArgumentError, "bad")
      expect(klass.new.label).to eq(:own)
    end

    it "copes with a method that has no source location" do
      klass.send(:alias_method, :shown, :inspect)

      expect { described_class.keeping(klass, file) { define_in(file, "def shown = :block") } }.not_to raise_error
      expect(klass.new.shown).not_to eq(:block)
    end

    it "leaves a method inherited from a parent to the parent" do
      parent = Class.new
      define_in("/app/parent.rb", "def label = :parent", on: parent)
      child = Class.new(parent)

      described_class.keeping(child, file) { define_in(file, "def label = :block", on: child) }

      expect(child.new.label).to eq(:block)
    end

    it "does not trust the class's own reflection methods" do
      define_in("/app/ledger.rb", <<~RUBY)
        def label = :own
        def self.public_instance_methods(*) = raise("not asked")
        def self.protected_instance_methods(*) = raise("not asked")
        def self.private_instance_methods(*) = raise("not asked")
        def self.instance_method(*) = raise("not asked")
        def self.method_defined?(*) = raise("not asked")
        def self.private_method_defined?(*) = raise("not asked")
        def self.define_method(*) = raise("not asked")
        def self.singleton_class = raise("not asked")
        def self.public(*) = raise("not asked")
      RUBY

      described_class.keeping(klass, file) { define_in(file, "def label = :block") }

      expect(klass.new.label).to eq(:own)
    end
  end
end
