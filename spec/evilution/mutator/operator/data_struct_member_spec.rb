# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::DataStructMember do
  def subjects_for(inline_source)
    tmpfile = Tempfile.new(["data_struct_member", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    yield Evilution::AST::Parser.new.call(tmpfile.path)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutations_for(inline_source, method_name, filter: nil)
    subjects_for(inline_source) do |subjects|
      subject = subjects.find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
      described_class.new.call(subject, filter: filter)
    end
  end

  def constant_mutations_for(inline_source, name)
    subjects_for(inline_source) do |subjects|
      subject = subjects.find { |s| s.kind == :constant && s.name == name }
      described_class.new.call(subject)
    end
  end

  # The line each mutation rewrote, so an expectation reads as the definition
  # the mutant would load.
  def mutated_lines(muts)
    muts.map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    context "with a definition inside a method body" do
      it "drops each member and swaps each adjacent pair of a Struct" do
        muts = mutations_for("class C\n  def build\n    Struct.new(:a, :b, :c)\n  end\nend\n", "build")

        expect(mutated_lines(muts)).to eq(
          [
            "Struct.new(:b, :c)",
            "Struct.new(:a, :c)",
            "Struct.new(:a, :b)",
            "Struct.new(:b, :a, :c)",
            "Struct.new(:a, :c, :b)"
          ]
        )
      end

      it "drops each member and swaps the pair of a Data definition" do
        muts = mutations_for("class C\n  def build\n    Data.define(:x, :y)\n  end\nend\n", "build")

        expect(mutated_lines(muts)).to eq(
          ["Data.define(:y)", "Data.define(:x)", "Data.define(:y, :x)"]
        )
      end

      it "matches a top-level constant path receiver" do
        muts = mutations_for("class C\n  def build\n    ::Struct.new(:a, :b)\n  end\nend\n", "build")

        expect(mutated_lines(muts)).to eq(
          ["::Struct.new(:b)", "::Struct.new(:a)", "::Struct.new(:b, :a)"]
        )
      end

      # A lone member has nothing to swap with, and dropping it would leave
      # `Struct.new()`, which raises on Rubies that require a member.
      it "emits nothing for a single member" do
        muts = mutations_for("class C\n  def build\n    Struct.new(:a)\n  end\nend\n", "build")

        expect(muts).to be_empty
      end

      it "emits nothing for a definition without members" do
        muts = mutations_for("class C\n  def build\n    Data.define\n  end\nend\n", "build")

        expect(muts).to be_empty
      end

      it "keeps the keyword_init option in place" do
        muts = mutations_for(
          "class C\n  def build\n    Struct.new(:a, :b, keyword_init: true)\n  end\nend\n", "build"
        )

        expect(mutated_lines(muts)).to eq(
          [
            "Struct.new(:b, keyword_init: true)",
            "Struct.new(:a, keyword_init: true)",
            "Struct.new(:b, :a, keyword_init: true)"
          ]
        )
      end

      # A leading string names the generated class; it is not a member.
      it "keeps the class-name string of a Struct in place" do
        muts = mutations_for("class C\n  def build\n    Struct.new(\"Pair\", :a, :b)\n  end\nend\n", "build")

        expect(mutated_lines(muts)).to eq(
          [
            "Struct.new(\"Pair\", :b)",
            "Struct.new(\"Pair\", :a)",
            "Struct.new(\"Pair\", :b, :a)"
          ]
        )
      end

      # A splat hides how many members there are and where they sit, so neither
      # a drop nor a swap can be placed.
      it "emits nothing when the members include a splat" do
        muts = mutations_for("class C\n  def build(names)\n    Struct.new(:a, *names)\n  end\nend\n", "build")

        expect(muts).to be_empty
      end

      it "emits nothing when a splat follows several members" do
        muts = mutations_for("class C\n  def build(names)\n    Struct.new(:a, :b, *names)\n  end\nend\n", "build")

        expect(muts).to be_empty
      end

      it "emits nothing when a member is not a literal" do
        muts = mutations_for("class C\n  def build(name)\n    Struct.new(:a, :b, name)\n  end\nend\n", "build")

        expect(muts).to be_empty
      end

      # Swapping two identical members would reproduce the original source.
      it "does not swap a pair of identical members" do
        muts = mutations_for("class C\n  def build\n    Struct.new(:a, :a, :b)\n  end\nend\n", "build")

        expect(mutated_lines(muts)).to eq(
          ["Struct.new(:a, :b)", "Struct.new(:a, :b)", "Struct.new(:a, :a)", "Struct.new(:a, :b, :a)"]
        )
      end

      it "reaches a definition used as the receiver of another call" do
        muts = mutations_for("class C\n  def build\n    Struct.new(:a, :b).new(1, 2)\n  end\nend\n", "build")

        expect(mutated_lines(muts)).to eq(
          ["Struct.new(:b).new(1, 2)", "Struct.new(:a).new(1, 2)", "Struct.new(:b, :a).new(1, 2)"]
        )
      end

      it "ignores a namespaced constant and a receiver that is not a constant" do
        muts = mutations_for(
          "class C\n  def build(klass)\n    Mine::Struct.new(:a, :b)\n    Mine::Data.define(:a, :b)\n    " \
          "(klass).new(:a, :b)\n    klass.new(:a, :b)\n  end\nend\n",
          "build"
        )

        expect(muts).to be_empty
      end

      it "keeps the block of the definition" do
        muts = mutations_for(
          "class C\n  def build\n    Struct.new(:a, :b) { def sum = a + b }\n  end\nend\n", "build"
        )

        expect(mutated_lines(muts)).to eq(
          [
            "Struct.new(:b) { def sum = a + b }",
            "Struct.new(:a) { def sum = a + b }",
            "Struct.new(:b, :a) { def sum = a + b }"
          ]
        )
      end

      it "ignores other receivers and other methods" do
        muts = mutations_for(
          "class C\n  def build\n    Other.new(:a, :b)\n    Struct.define(:a, :b)\n    Data.new(:a, :b)\n    new(:a, :b)\n  end\nend\n",
          "build"
        )

        expect(muts).to be_empty
      end
    end

    context "with a definition outside any method" do
      let(:superclass_source) do
        "class Coord < Data.define(:lat, :lng)\n  def north? = lat.positive?\n\n  def east? = lng.positive?\nend\n"
      end

      it "mutates a superclass definition through the class's constant subject" do
        muts = constant_mutations_for(superclass_source, "Coord")

        expect(mutated_lines(muts)).to eq(
          [
            "class Coord < Data.define(:lng)",
            "class Coord < Data.define(:lat)",
            "class Coord < Data.define(:lng, :lat)"
          ]
        )
        expect(muts.map(&:subject).map(&:name).uniq).to eq(["Coord"])
      end

      # The definition has a subject of its own, so the methods of the class
      # do not repeat its mutants.
      it "leaves the definition out of the methods of the class" do
        expect(mutations_for(superclass_source, "north?")).to be_empty
        expect(mutations_for(superclass_source, "east?")).to be_empty
      end

      it "mutates a constant assigned in a class body" do
        muts = constant_mutations_for("class Shape\n  Size = Struct.new(:w, :h)\n\n  def area(size) = size.w * size.h\nend\n",
                                      "Shape::Size")

        expect(mutated_lines(muts)).to eq(
          ["Size = Struct.new(:h)", "Size = Struct.new(:w)", "Size = Struct.new(:h, :w)"]
        )
      end

      it "mutates a definition in a module without methods" do
        muts = constant_mutations_for("module Geo\n  Point = Data.define(:x, :y)\nend\n", "Geo::Point")

        expect(mutated_lines(muts)).to eq(
          ["Point = Data.define(:y)", "Point = Data.define(:x)", "Point = Data.define(:y, :x)"]
        )
      end

      it "mutates a bare top-level definition" do
        muts = constant_mutations_for("Pair = Struct.new(:left, :right)\n", "Pair")

        expect(mutated_lines(muts)).to eq(
          ["Pair = Struct.new(:right)", "Pair = Struct.new(:left)", "Pair = Struct.new(:right, :left)"]
        )
      end

      it "mutates a definition with a block, keeping the block" do
        muts = constant_mutations_for("Size = Struct.new(:w, :h) do\n  def area = w * h\nend\n", "Size")

        expect(mutated_lines(muts)).to eq(
          ["Size = Struct.new(:h) do", "Size = Struct.new(:w) do", "Size = Struct.new(:h, :w) do"]
        )
        expect(mutations_for("Size = Struct.new(:w, :h) do\n  def area = w * h\nend\n", "area")).to be_empty
      end

      # A definition nested in the block of another has a subject of its own;
      # the outer subject mutates only its own member list.
      it "leaves a definition nested in the block to its own subject" do
        source = "class Shape\n  Size = Struct.new(:w, :h) do\n    self::Unit = Data.define(:n, :s)\n  end\nend\n"

        expect(mutated_lines(constant_mutations_for(source, "Shape::Size"))).to eq(
          ["Size = Struct.new(:h) do", "Size = Struct.new(:w) do", "Size = Struct.new(:h, :w) do"]
        )
        expect(mutated_lines(constant_mutations_for(source, "Shape::Size::Unit"))).to eq(
          ["self::Unit = Data.define(:s)", "self::Unit = Data.define(:n)", "self::Unit = Data.define(:s, :n)"]
        )
      end

      it "does not emit a method-body definition twice" do
        muts = mutations_for("class C\n  def build\n    Struct.new(:a, :b)\n  end\nend\n", "build")

        expect(muts.length).to eq(3)
      end
    end

    it "produces parseable mutations" do
      source = "class Coord < Data.define(:lat, :lng, :alt)\n  def build = Struct.new(:a, :b, keyword_init: true)\nend\n"
      muts = constant_mutations_for(source, "Coord") + mutations_for(source, "build")

      expect(muts.length).to eq(8)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "accepts method and constant subjects" do
      expect(described_class.subject_kinds).to eq(%i[method constant])
    end

    it "sets the operator name" do
      muts = mutations_for("class C\n  def build\n    Struct.new(:a, :b)\n  end\nend\n", "build")

      expect(muts.map(&:operator_name).uniq).to eq(["data_struct_member"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=new}"])

      muts = mutations_for("class C\n  def build\n    Struct.new(:a, :b)\n  end\nend\n", "build", filter: filter)

      expect(muts).to be_empty
    end
  end
end
