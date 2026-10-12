# frozen_string_literal: true

require "evilution/integration/loading/concern_redeclaration"

RSpec.describe Evilution::Integration::Loading::ConcernRedeclaration do
  # A concern, as far as this module cares: something classes include that
  # holds the block its `included` call registered.
  def concern_with(&block)
    Module.new.tap { |mod| mod.instance_variable_set(:@_included_block, block) if block }
  end

  describe ".skipping?" do
    it "is false outside a redeclaration" do
      expect(described_class.skipping?).to be(false)
    end
  end

  describe ".call" do
    it "runs the registered block on each class that includes the concern" do
      concern = concern_with { define_singleton_method(:marked) { :yes } }
      first = Class.new { include concern }
      second = Class.new { include concern }

      described_class.call(concern)

      expect([first.marked, second.marked]).to eq(%i[yes yes])
    end

    it "runs the block as the class, like the include did" do
      seen = []
      concern = concern_with { seen << self }
      includer = Class.new { include concern }

      described_class.call(concern)

      expect(seen).to eq([includer])
    end

    it "reports skipping while the block runs, and not afterwards" do
      observed = []
      concern = concern_with { observed << Evilution::Integration::Loading::ConcernRedeclaration.skipping? }
      Class.new { include concern }

      described_class.call(concern)

      expect(observed).to eq([true])
      expect(described_class.skipping?).to be(false)
    end

    it "stops skipping when the block raises" do
      concern = concern_with { raise ArgumentError, "bad scope" }
      Class.new { include concern }

      expect { described_class.call(concern) }.to raise_error(ArgumentError, "bad scope")
      expect(described_class.skipping?).to be(false)
    end

    it "leaves a subclass to inherit from the class that includes the concern" do
      seen = []
      concern = concern_with { seen << self }
      parent = Class.new { include concern }
      Class.new(parent)

      described_class.call(concern)

      expect(seen).to eq([parent])
    end

    it "leaves classes that do not include the concern alone" do
      seen = []
      concern = concern_with { seen << self }
      Class.new

      described_class.call(concern)

      expect(seen).to eq([])
    end

    it "does not trust a class's own include? or superclass" do
      seen = []
      concern = concern_with { seen << self }
      odd = Class.new do
        include concern

        def self.include?(*) = raise("not a module question")
        def self.superclass = raise("not asked")
      end

      described_class.call(concern)

      expect(seen).to eq([odd])
    end

    it "does nothing for a concern with no registered block" do
      concern = concern_with
      Class.new { include concern }

      expect { described_class.call(concern) }.not_to raise_error
    end

    describe "a method the class defined over one of the block" do
      # Defined from another file, as a class's own methods are: the block's
      # are told apart by the file they were written in.
      def define_elsewhere(klass, code)
        klass.class_eval(code, "/elsewhere/own.rb", 1)
      end

      it "is kept, instance or singleton" do
        concern = concern_with do
          def label = :block
          def self.level = :block
        end
        includer = Class.new { include concern }
        define_elsewhere(includer, "def label = :own\ndef self.level = :own")

        described_class.call(concern)

        expect([includer.new.label, includer.level]).to eq(%i[own own])
      end

      it "keeps its visibility" do
        concern = concern_with do
          def hidden = :block
          def guarded = :block
        end
        includer = Class.new { include concern }
        define_elsewhere(includer, "private def hidden = :own\nprotected def guarded = :own")

        described_class.call(concern)

        expect(includer.private_instance_methods(false)).to include(:hidden)
        expect(includer.protected_instance_methods(false)).to include(:guarded)
        expect(includer.new.send(:hidden)).to eq(:own)
      end

      it "is kept when the block raises" do
        concern = concern_with do
          def label = :block
          raise ArgumentError, "bad" if Evilution::Integration::Loading::ConcernRedeclaration.skipping?
        end
        includer = Class.new { include concern }
        define_elsewhere(includer, "def label = :own")

        expect { described_class.call(concern) }.to raise_error(ArgumentError, "bad")
        expect(includer.new.label).to eq(:own)
      end

      it "does not stand in the way of the block's own methods, or of ones it adds" do
        concern = concern_with do
          def label = :second
          def added = :block
        end
        includer = Class.new { include concern }
        includer.class_eval { def label = :first }
        define_elsewhere(includer, "def other = :own")

        described_class.call(concern)

        expect([includer.new.label, includer.new.added, includer.new.other]).to eq(%i[second block own])
      end

      it "leaves a method the block removes removed" do
        concern = concern_with do
          remove_method(:gone) if Evilution::Integration::Loading::ConcernRedeclaration.skipping?
        end
        includer = Class.new { include concern }
        define_elsewhere(includer, "def gone = :own")

        described_class.call(concern)

        expect(includer.method_defined?(:gone)).to be(false)
      end

      it "does not trust the class's own reflection methods" do
        concern = concern_with { def label = :block }
        includer = Class.new { include concern }
        define_elsewhere(includer, <<~RUBY)
          def label = :own
          def self.instance_methods(*) = raise("not asked")
          def self.private_instance_methods(*) = raise("not asked")
          def self.instance_method(*) = raise("not asked")
          def self.define_method(*) = raise("not asked")
        RUBY

        expect { described_class.call(concern) }.not_to raise_error
        expect(includer.new.label).to eq(:own)
      end
    end

    it "leaves a class that prepends the concern alone" do
      seen = []
      concern = concern_with { seen << self }
      Class.new { prepend concern }

      described_class.call(concern)

      expect(seen).to eq([])
    end
  end

  describe ".call for the prepended block" do
    def concern_prepending(&block)
      Module.new.tap { |mod| mod.instance_variable_set(:@_prepended_block, block) if block }
    end

    it "runs the registered block as each class that prepends the concern" do
      seen = []
      concern = concern_prepending { seen << self }
      first = Class.new { prepend concern }
      second = Class.new { prepend concern }

      described_class.call(concern, :prepended)

      expect(seen).to contain_exactly(first, second)
    end

    it "reports skipping while the block runs" do
      observed = []
      concern = concern_prepending { observed << Evilution::Integration::Loading::ConcernRedeclaration.skipping? }
      Class.new { prepend concern }

      described_class.call(concern, :prepended)

      expect(observed).to eq([true])
    end

    it "leaves a class that includes the concern alone" do
      seen = []
      concern = concern_prepending { seen << self }
      Class.new { include concern }

      described_class.call(concern, :prepended)

      expect(seen).to eq([])
    end

    it "leaves a subclass to inherit from the class that prepends the concern" do
      seen = []
      concern = concern_prepending { seen << self }
      parent = Class.new { prepend concern }
      Class.new(parent)

      described_class.call(concern, :prepended)

      expect(seen).to eq([parent])
    end

    it "does not run the included block" do
      seen = []
      concern = concern_prepending { seen << :prepended }
      concern.instance_variable_set(:@_included_block, proc { seen << :included })
      Class.new { prepend concern }

      described_class.call(concern, :prepended)

      expect(seen).to eq([:prepended])
    end

    it "does nothing for a concern with no prepended block" do
      concern = concern_with { raise "not this one" }
      Class.new { prepend concern }

      expect { described_class.call(concern, :prepended) }.not_to raise_error
    end

    it "refuses a hook it does not know" do
      expect { described_class.call(concern_with, :extended) }.to raise_error(KeyError)
    end
  end
end
