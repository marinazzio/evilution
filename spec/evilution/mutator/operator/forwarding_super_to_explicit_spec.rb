# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ForwardingSuperToExplicit do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/forwarding_super_to_explicit.rb", __dir__)
  end
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def subject_for(method_name)
    subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
  end

  def mutations_for(method_name)
    described_class.new.call(subject_for(method_name))
  end

  # Isolate the mutated method so an expectation reads as the resulting source
  # rather than a byte offset.
  def mutated_bodies(muts, method_name)
    muts.map { |m| m.mutated_source[/  def (?:self\.)?#{method_name}\b.*?\n  end\n/m] }
  end

  def mutations_from_source(inline_source, method_name: nil)
    tmpfile = Tempfile.new(["forwarding_super_to_explicit", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects = subjects.select { |s| s.name.end_with?("##{method_name}", ".#{method_name}") } if method_name
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  describe "#call" do
    it "makes a forwarding super explicit when the method takes a positional parameter" do
      muts = mutations_for("positional")

      expect(mutated_bodies(muts, "positional")).to eq(["  def positional(value)\n    super()\n  end\n"])
    end

    it "mutates when the method takes an optional parameter" do
      muts = mutations_for("optional")

      expect(mutated_bodies(muts, "optional")).to eq(["  def optional(value = 1)\n    super()\n  end\n"])
    end

    it "mutates when the method takes a keyword parameter" do
      muts = mutations_for("keyword")

      expect(mutated_bodies(muts, "keyword")).to eq(["  def keyword(key: 1)\n    super()\n  end\n"])
    end

    it "mutates when the method takes a splat" do
      muts = mutations_for("splat")

      expect(mutated_bodies(muts, "splat")).to eq(["  def splat(*args)\n    super()\n  end\n"])
    end

    it "mutates when the method forwards everything with ..." do
      muts = mutations_for("forwarding")

      expect(mutated_bodies(muts, "forwarding")).to eq(["  def forwarding(...)\n    super()\n  end\n"])
    end

    # The parentheses go after the keyword, so a block written on the super
    # stays where it is.
    it "keeps a block attached to the super" do
      muts = mutations_for("with_block_argument")

      expect(mutated_bodies(muts, "with_block_argument")).to eq(
        ["  def with_block_argument(value)\n    super() { 1 }\n  end\n"]
      )
    end

    # A block shares the method's scope, so a super inside one still forwards
    # the method's arguments.
    it "mutates a super written inside a block" do
      muts = mutations_for("inside_a_block")

      expect(mutated_bodies(muts, "inside_a_block")).to eq(
        ["  def inside_a_block(value)\n    [1, 2].each { super() }\n  end\n"]
      )
    end

    it "mutates a super among other statements" do
      muts = mutations_for("among_statements")

      expect(mutated_bodies(muts, "among_statements")).to eq(
        ["  def among_statements(value)\n    prepare\n    super()\n  end\n"]
      )
    end

    it "mutates the super of an endless method" do
      muts = mutations_for("endless_super")

      expect(muts.map { |m| m.mutated_source[/  def endless_super.*$/] }).to eq(
        ["  def endless_super(value) = super()"]
      )
    end

    it "mutates the super of a singleton method" do
      muts = mutations_for("singleton")

      expect(mutated_bodies(muts, "singleton")).to eq(
        ["  def self.singleton(value)\n    super()\n  end\n"]
      )
    end

    it "mutates when the method takes a post-required parameter" do
      muts = mutations_for("post_required")

      expect(mutated_bodies(muts, "post_required")).to eq(
        ["  def post_required(*rest, last)\n    super()\n  end\n"]
      )
    end

    # The inner def is popped off once it has been visited, so the super that
    # follows it is still answered with the outer method's parameters.
    it "mutates a super written after a nested def" do
      muts = mutations_for("super_after_inner_def")

      expect(mutated_bodies(muts, "super_after_inner_def")).to eq(
        ["  def super_after_inner_def(value)\n    def paramless_helper\n      1\n    end\n    super()\n  end\n"]
      )
    end

    # The block hangs off the super node, so reaching the inner one means
    # descending through it.
    it "mutates a super written inside the block of another super" do
      muts = mutations_for("super_inside_super_block")

      expect(mutated_bodies(muts, "super_inside_super_block")).to contain_exactly(
        "  def super_inside_super_block(value)\n    super() { super }\n  end\n",
        "  def super_inside_super_block(value)\n    super { super() }\n  end\n"
      )
    end

    # `super()` still passes the block, so with nothing but a block parameter
    # the two forms behave identically.
    it "emits nothing when the method takes only a block parameter" do
      expect(mutations_for("block_only")).to be_empty
    end

    it "emits nothing when the method takes no parameters" do
      expect(mutations_for("no_parameters")).to be_empty
    end

    # ExplicitSuperMutation owns a super that already lists its arguments.
    it "emits nothing for an explicit super" do
      expect(mutations_for("explicit_super")).to be_empty
    end

    it "emits nothing for a method without a super" do
      expect(mutations_for("no_super")).to be_empty
    end

    # The inner def opens its own argument list, so its super forwards the
    # inner parameters.
    it "uses the parameters of the innermost enclosing method" do
      muts = mutations_for("outer_with_inner")

      expect(mutated_bodies(muts, "outer_with_inner")).to eq(
        ["  def outer_with_inner(value)\n    def inner(other)\n      super()\n    end\n  end\n"]
      )
    end

    it "emits nothing when the innermost enclosing method takes no parameters" do
      expect(mutations_for("outer_with_paramless_inner")).to be_empty
    end

    it "mutates each super of a method that has several" do
      muts = mutations_from_source(
        "def m(value)\n  super if value\n  super unless value\nend\n"
      )

      expect(muts.map(&:mutated_source)).to eq(
        [
          "def m(value)\n  super() if value\n  super unless value\nend\n",
          "def m(value)\n  super if value\n  super() unless value\nend\n"
        ]
      )
    end

    it "reports the mutation on the line of the super" do
      muts = mutations_for("among_statements")

      expect(muts.map(&:line)).to eq([35])
    end

    it "names the operator" do
      muts = mutations_for("positional")

      expect(muts.map(&:operator_name)).to eq(["forwarding_super_to_explicit"])
    end

    it "produces parseable mutations" do
      muts = mutations_for("positional") + mutations_for("with_block_argument") +
             mutations_for("endless_super") + mutations_for("forwarding")

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["forwarding_super"])

      muts = described_class.new.call(subject_for("positional"), filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
