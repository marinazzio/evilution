# frozen_string_literal: true

require "evilution/integration/loading/frozen_namespaces"

RSpec.describe Evilution::Integration::Loading::FrozenNamespaces do
  # Defined by hand rather than with stub_const: the examples remove them, and
  # stub_const cannot reset a constant that is gone.
  before do
    Object.const_set(:EkaxFrozenOuter, Module.new)
    EkaxFrozenOuter.const_set(:Inner, Class.new)
    Object.const_set(:EkaxFrozenOther, Class.new)
  end

  after do
    %i[EkaxFrozenOuter EkaxFrozenOther].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
  end

  # A load that records what the probe sees each time it runs, and raises the
  # given errors in turn.
  def attempts(errors, seen = [])
    lambda do |&probe|
      seen << probe.call
      error = errors.shift
      raise error if error

      :loaded
    end
  end

  def freeze_error(receiver)
    FrozenError.new("can't modify frozen #{receiver.class}: #{receiver}", receiver: receiver)
  end

  describe "#recover" do
    it "returns what the block returns when it raises nothing" do
      namespaces = described_class.taken(%w[EkaxFrozenOuter EkaxFrozenOuter::Inner])

      expect(namespaces.recover { :loaded }).to eq(:loaded)
    end

    it "sets aside a declared class a later freeze stopped, then runs the block once more" do
      namespaces = described_class.taken(%w[EkaxFrozenOuter EkaxFrozenOuter::Inner])
      frozen = EkaxFrozenOuter::Inner.freeze
      seen = []
      attempt = attempts([freeze_error(frozen)], seen)

      result = namespaces.recover { attempt.call { EkaxFrozenOuter.const_defined?(:Inner, false) } }

      expect(result).to eq(:loaded)
      expect(seen).to eq([true, false])
      expect(EkaxFrozenOuter.const_defined?(:Inner, false)).to be(false)
    end

    it "sets aside only the class the error names, keeping its namespace" do
      namespaces = described_class.taken(%w[EkaxFrozenOuter EkaxFrozenOuter::Inner])
      outer = EkaxFrozenOuter
      attempt = attempts([freeze_error(EkaxFrozenOuter::Inner.freeze)])

      namespaces.recover { attempt.call { nil } }

      expect(Object.const_get(:EkaxFrozenOuter, false)).to equal(outer)
    end

    it "sets aside a top-level class" do
      namespaces = described_class.taken(%w[EkaxFrozenOther])
      attempt = attempts([freeze_error(EkaxFrozenOther.freeze)])

      namespaces.recover { attempt.call { nil } }

      expect(Object.const_defined?(:EkaxFrozenOther, false)).to be(false)
    end

    it "sets aside a declared class that was not loaded yet when taken" do
      namespaces = described_class.taken(%w[EkaxFrozenOuter::Later])
      later = Class.new.freeze
      EkaxFrozenOuter.const_set(:Later, later)
      attempt = attempts([freeze_error(later)])

      expect(namespaces.recover { attempt.call { nil } }).to eq(:loaded)
      expect(EkaxFrozenOuter.const_defined?(:Later, false)).to be(false)
    end

    it "lets the error through, keeping the class, when the class was frozen already" do
      frozen = EkaxFrozenOther.freeze
      namespaces = described_class.taken(%w[EkaxFrozenOther])
      seen = []
      attempt = attempts([freeze_error(frozen)], seen)

      expect { namespaces.recover { attempt.call { :tried } } }
        .to raise_error(FrozenError, "can't modify frozen Class: #{frozen}")
      expect(seen).to eq([:tried])
      expect(Object.const_get(:EkaxFrozenOther, false)).to equal(frozen)
    end

    it "lets the error through when the frozen class is not one the source declares" do
      namespaces = described_class.taken(%w[EkaxFrozenOuter EkaxFrozenOuter::Inner])
      seen = []
      attempt = attempts([freeze_error(EkaxFrozenOther.freeze)], seen)

      expect { namespaces.recover { attempt.call { :tried } } }.to raise_error(FrozenError)
      expect(seen).to eq([:tried])
      expect(EkaxFrozenOuter.const_defined?(:Inner, false)).to be(true)
    end

    it "lets the error through when what is frozen is not a namespace" do
      namespaces = described_class.taken(%w[EkaxFrozenOther])
      seen = []
      attempt = attempts([freeze_error("text")], seen)

      expect { namespaces.recover { attempt.call { :tried } } }.to raise_error(FrozenError)
      expect(seen).to eq([:tried])
      expect(Object.const_defined?(:EkaxFrozenOther, false)).to be(true)
    end

    it "lets the error through when it names no receiver" do
      namespaces = described_class.taken(%w[EkaxFrozenOther])
      attempt = attempts([FrozenError.new("frozen")])

      expect { namespaces.recover { attempt.call { nil } } }.to raise_error(FrozenError, "frozen")
      expect(Object.const_defined?(:EkaxFrozenOther, false)).to be(true)
    end

    it "runs the block once more at most" do
      namespaces = described_class.taken(%w[EkaxFrozenOther])
      first = EkaxFrozenOther.freeze
      seen = []
      attempt = attempts([freeze_error(first), ArgumentError.new("still broken")], seen)

      expect { namespaces.recover { attempt.call { :tried } } }.to raise_error(ArgumentError, "still broken")
      expect(seen).to eq(%i[tried tried])
    end

    it "lets an error other than FrozenError through untouched, though it names a declared class" do
      namespaces = described_class.taken(%w[EkaxFrozenOther])
      seen = []
      attempt = attempts([NoMethodError.new("undefined method 'size'", :size, receiver: EkaxFrozenOther.freeze)], seen)

      expect { namespaces.recover { attempt.call { :tried } } }.to raise_error(NoMethodError, "undefined method 'size'")
      expect(seen).to eq([:tried])
      expect(Object.const_defined?(:EkaxFrozenOther, false)).to be(true)
    end

    # `Sub::Inner` resolves to `Base::Inner` when inherited constants count;
    # the source declares a class of Sub's own.
    context "when the declared class is not loaded but its superclass has one of that name" do
      before do
        Object.const_set(:EkaxFrozenBase, Class.new)
        EkaxFrozenBase.const_set(:Inner, Class.new)
        Object.const_set(:EkaxFrozenSub, Class.new(EkaxFrozenBase))
      end

      after do
        %i[EkaxFrozenSub EkaxFrozenBase].each { |name| Object.send(:remove_const, name) }
      end

      it "does not take the inherited class for it" do
        inherited = EkaxFrozenBase::Inner
        namespaces = described_class.taken(%w[EkaxFrozenSub EkaxFrozenSub::Inner])
        attempt = attempts([freeze_error(inherited.freeze)])

        expect { namespaces.recover { attempt.call { nil } } }.to raise_error(FrozenError)
        expect(EkaxFrozenBase.const_get(:Inner, false)).to equal(inherited)
      end

      it "takes it as not frozen though the inherited one is, so freezing it later is set aside" do
        EkaxFrozenBase::Inner.freeze
        namespaces = described_class.taken(%w[EkaxFrozenSub::Inner])
        own = EkaxFrozenSub.const_set(:Inner, Class.new).freeze
        seen = []
        attempt = attempts([freeze_error(own)], seen)

        expect(namespaces.recover { attempt.call { EkaxFrozenSub.const_defined?(:Inner, false) } }).to eq(:loaded)
        expect(seen).to eq([true, false])
      end
    end

    it "finds the frozen class past a declared name that is not defined when the error is raised" do
      namespaces = described_class.taken(%w[EkaxFrozenNotYet EkaxFrozenOther])
      attempt = attempts([freeze_error(EkaxFrozenOther.freeze)])

      expect(namespaces.recover { attempt.call { nil } }).to eq(:loaded)
      expect(Object.const_defined?(:EkaxFrozenOther, false)).to be(false)
    end
  end

  it "keeps how it finds and removes a frozen class to itself" do
    expect(described_class.private_instance_methods(false)).to contain_exactly(:initialize, :frozen_since_taken, :put_aside)
  end

  describe "NONE" do
    it "declares nothing, so a frozen class's error goes through" do
      attempt = attempts([freeze_error(EkaxFrozenOther.freeze)])

      expect { described_class::NONE.recover { attempt.call { nil } } }.to raise_error(FrozenError)
      expect(Object.const_defined?(:EkaxFrozenOther, false)).to be(true)
    end

    it "is frozen" do
      expect(described_class::NONE).to be_frozen
    end
  end
end
