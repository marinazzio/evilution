# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::KeywordArgumentRemoval do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/keyword_argument_removal.rb", __dir__)
  end
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  def mutations_from_source(inline_source)
    tmpfile = Tempfile.new(["keyword_argument_removal", ".rb"])
    tmpfile.write(inline_source)
    tmpfile.flush
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)
    subjects.flat_map { |s| described_class.new.call(s) }
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "drops each keyword argument in turn" do
      expect(mutated_lines(mutations_for("two_keywords")))
        .to contain_exactly("build(size: 2)", 'build(name: "x")')
    end

    it "drops a keyword that follows a positional argument" do
      expect(mutated_lines(mutations_for("positional_and_keyword"))).to eq(["build(value)"])
    end

    it "drops keywords from a multi-line call" do
      sources = mutations_for("multiline").map(&:mutated_source)

      expect(sources).to contain_exactly(
        a_string_including("build(\n      size: 2\n    )"),
        a_string_including("build(\n      name: \"x\"\n    )")
      )
    end

    it "keeps a double splat and never drops it" do
      expect(mutated_lines(mutations_for("with_double_splat"))).to eq(["build(**opts)"])
    end

    it "drops a pair that follows a double splat" do
      muts = mutations_from_source("def a(opts)\n  build(**opts, name: 1)\nend\n")

      expect(mutated_lines(muts)).to eq(["build(**opts)"])
    end

    it "drops keywords nested in another keyword's value" do
      muts = mutations_from_source("def a\n  f(x: g(p: 1, q: 2), y: 3)\nend\n")

      expect(mutated_lines(muts)).to contain_exactly(
        "f(y: 3)", "f(x: g(p: 1, q: 2))", "f(x: g(q: 2), y: 3)", "f(x: g(p: 1), y: 3)"
      )
    end

    it "drops string-keyed pairs" do
      expect(mutated_lines(mutations_for("string_keys")))
        .to contain_exactly('build("size" => 2)', 'build("name" => "x")')
    end

    it "drops shorthand keywords" do
      expect(mutated_lines(mutations_for("shorthand"))).to contain_exactly("build(size:)", "build(name:)")
    end

    it "keeps a block-pass argument" do
      expect(mutated_lines(mutations_for("with_block_pass")))
        .to contain_exactly("build(size: 2, &block)", 'build(name: "x", &block)')
    end

    it "handles a call without parentheses" do
      expect(mutated_lines(mutations_for("without_parens")))
        .to contain_exactly("build size: 2", 'build name: "x"')
    end

    it "drops keywords passed to super" do
      muts = mutations_from_source("class A < B\n  def go\n    super(name: 1, size: 2)\n  end\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("super(size: 2)", "super(name: 1)")
    end

    # The heredoc-span extension would sweep the rest of the anchor line along
    # with the body, so dropping a heredoc-valued keyword does not parse and is
    # skipped rather than reported as unparseable.
    it "skips dropping a heredoc-valued keyword but still drops its neighbour" do
      muts = mutations_from_source("def a\n  f(x: <<~T, y: 1)\n    body\n  T\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def a\n  f(x: <<~T)\n    body\n  T\nend\n"])
    end

    it "skips a lone keyword that is the only argument, which argument_list_removal covers" do
      expect(mutations_for("lone_keyword")).to be_empty
    end

    it "leaves an explicit hash literal alone" do
      expect(mutations_for("hash_literal")).to be_empty
    end

    it "reports the mutation on the line of the dropped keyword" do
      expect(mutations_for("multiline").map(&:line)).to contain_exactly(12, 13)
    end

    it "names the operator" do
      expect(mutations_for("two_keywords").map(&:operator_name).uniq).to eq(["keyword_argument_removal"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["assoc"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#two_keywords") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(2)
    end
  end
end
