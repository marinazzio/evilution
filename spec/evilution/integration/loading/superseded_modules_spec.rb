# frozen_string_literal: true

require "evilution/integration/loading/superseded_modules"

RSpec.describe Evilution::Integration::Loading::SupersededModules do
  subject(:superseded) { described_class.new(registry: {}) }

  let(:file_path) { "/evilution/superseded_modules_spec/target.rb" }
  let(:other_path) { "/evilution/superseded_modules_spec/other.rb" }
  let(:host) { Object.new }

  # Evaluates `source` as the given file, the way SourceEvaluator does, with
  # `host` reachable from it.
  def evaluate(source, path = file_path, tracker: superseded)
    tracker.track(path) { eval(source, binding, path, 1) } # rubocop:disable Security/Eval
  end

  def install(version, path = file_path, tracker: superseded)
    evaluate(<<~RUBY, path, tracker: tracker)
      host.extend(Module.new do
        def seen
          [:#{version}] + (defined?(super) ? super : [])
        end
      end)
    RUBY
  end

  describe "#track" do
    it "returns the value of the block" do
      expect(superseded.track(file_path) { :evaluated }).to eq(:evaluated)
    end

    # A file that extends an object with `Module.new` leaves one more module
    # on that object every time it is evaluated, and Ruby cannot take one
    # off. In-process isolation evaluates the file once per mutation, so the
    # current mutation's `super` used to run every earlier mutation's code.
    it "empties the anonymous module an earlier evaluation of the file installed" do
      install(:first)
      install(:second)

      expect(host.seen).to eq([:second])
    end

    it "leaves the module of the latest evaluation alone" do
      install(:first)

      expect(host.seen).to eq([:first])
    end

    it "empties only the evaluation before the last, not the one that follows it" do
      install(:first)
      install(:second)
      install(:third)

      expect(host.seen).to eq([:third])
    end

    it "leaves a module installed by another file alone" do
      install(:other, other_path)
      install(:first)
      install(:second)

      expect(host.seen).to eq(%i[second other])
    end

    it "keeps the evaluations of two files apart" do
      install(:first)
      install(:other, other_path)
      install(:second)

      expect(host.seen).to eq(%i[second other])
    end

    it "removes private methods as well" do
      evaluate("host.extend(Module.new { private def hidden = :first })")
      evaluate("nil")

      expect(host.respond_to?(:hidden, true)).to be(false)
    end

    it "leaves a module that got a name alone" do
      evaluate("EvilutionSupersededNamed = Module.new { def named = :first }; host.extend(EvilutionSupersededNamed)")
      evaluate("nil")

      expect(host.named).to eq(:first)
    ensure
      Object.send(:remove_const, :EvilutionSupersededNamed) if defined?(EvilutionSupersededNamed)
    end

    it "leaves an anonymous class alone" do
      klass = evaluate("Class.new { def kept = :first }")
      evaluate("nil")

      expect(klass.new.kept).to eq(:first)
    end

    # A module the evaluation caused some library to build is the library's:
    # its methods were not written in the file, and evaluating the file again
    # does not replace them.
    it "leaves methods that were not written in the file alone" do
      evaluate(<<~RUBY)
        generated = Module.new
        generated.module_eval("def generated = :kept", "/somewhere/else/library.rb", 1)
        host.extend(generated)
      RUBY
      evaluate("nil")

      expect(host.generated).to eq(:kept)
    end

    it "removes only the file's own methods from a module that has both kinds" do
      evaluate(<<~RUBY)
        mixed = Module.new { def own = :first }
        mixed.module_eval("def generated = :kept", "/somewhere/else/library.rb", 1)
        host.extend(mixed)
      RUBY
      evaluate("nil")

      expect(host).to respond_to(:generated)
      expect(host).not_to respond_to(:own)
    end

    it "passes over a frozen module" do
      evaluate("host.extend(Module.new { def frozen_one = :first }.freeze)")

      expect { evaluate("nil") }.not_to raise_error
      expect(host.frozen_one).to eq(:first)
    end

    it "remembers the modules of an evaluation that raised" do
      expect do
        evaluate("host.extend(Module.new { def seen = [:broken] }); raise 'load failed'")
      end.to raise_error("load failed")

      install(:second)
      install(:third)

      expect(host.seen).to eq([:third])
    end

    # ActiveSupport's DeprecatedConstantProxy subclasses Module and undefines
    # nearly every method, so ObjectSpace yields it and any message it gets
    # lands in method_missing, which emits the deprecation. A project that
    # raises on deprecations turns a message to it into an exception.
    it "sends no message to a module that intercepts them" do
      touched = []
      proxy_class = Class.new(Module) do
        instance_methods.each { |m| undef_method(m) unless /^__|^object_id$/.match?(m) }

        define_method(:method_missing) do |name, *_args|
          touched << name
          raise "deprecated constant touched via ##{name}"
        end
      end
      proxy = proxy_class.new

      expect { install(:first) }.not_to raise_error
      expect(touched).to eq([])
      expect(proxy.__id__).to be_an(Integer) # keeps the proxy alive across the scan
    end

    it "takes a module for anonymous by Module's own name, not by one it defines" do
      evaluate(<<~RUBY)
        host.extend(Module.new do
          def self.name = "Pretending"
          def seen = [:first]
        end)
      RUBY
      evaluate("nil")

      expect(host).not_to respond_to(:seen)
    end

    # Most files create no anonymous module. One entry per file ever evaluated
    # would only be something to carry through the run.
    describe "what it keeps on record" do
      let(:registry) { {} }
      let(:superseded) { described_class.new(registry: registry) }

      it "keeps nothing for an evaluation that created no anonymous module" do
        evaluate("nil")

        expect(registry).to eq({})
      end

      it "keeps the file's entry while there is a module to empty" do
        install(:first)

        expect(registry.keys).to eq([file_path])
      end

      it "drops the file's entry once the next evaluation created none" do
        install(:first)
        evaluate("nil")

        expect(registry).to eq({})
      end
    end

    it "does not empty a module twice" do
      install(:first)
      install(:second)
      evaluate("nil")

      expect { evaluate("nil") }.not_to raise_error
      expect(host).not_to respond_to(:seen)
    end
  end

  # Walking the heap is cheap in a process that has been running and dear in
  # one just forked, where every page it touches has to be mapped first: fork
  # runs of four canaries took 40% longer with the walk in each child. A fork
  # child evaluates one mutation and ends, so it has nothing to protect.
  describe "in a process that ends with its mutation" do
    around do |example|
      previous = Evilution.instance_variable_get(:@single_mutation_process)
      Evilution.single_mutation_process!
      example.run
    ensure
      Evilution.instance_variable_set(:@single_mutation_process, previous)
    end

    it "still evaluates the block and returns its value" do
      expect(superseded.track(file_path) { :evaluated }).to eq(:evaluated)
    end

    it "does not walk the heap" do
      expect(ObjectSpace).not_to receive(:each_object)

      superseded.track(file_path) { nil }
    end

    it "records nothing" do
      registry = {}

      described_class.new(registry: registry).track(file_path) { Module.new }

      expect(registry).to eq({})
    end
  end

  describe "the shared registry" do
    after { described_class.registry.delete(file_path) }

    it "is what a new instance records in" do
      install(:first, tracker: described_class.new)
      install(:second, tracker: described_class.new)

      expect(host.seen).to eq([:second])
    end
  end
end
