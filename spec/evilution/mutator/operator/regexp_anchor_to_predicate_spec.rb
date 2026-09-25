# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpAnchorToPredicate do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/regexp_anchor_to_predicate.rb", __dir__)
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
    tmpfile = Tempfile.new(["regexp_anchor_to_predicate", ".rb"])
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
    it "rewrites a line-start anchor to start_with?" do
      expect(mutated_lines(mutations_for("line_prefix"))).to eq(['line.start_with?("foo")'])
    end

    it "rewrites a string-start anchor used with =~, whose return value differs" do
      expect(mutated_lines(mutations_for("string_prefix_match"))).to eq(['line.start_with?("foo")'])
    end

    it "rewrites a line-end anchor to end_with?" do
      expect(mutated_lines(mutations_for("dollar_suffix"))).to eq(['line.end_with?("bar")'])
    end

    it "rewrites a \\Z anchor to end_with?" do
      expect(mutated_lines(mutations_for("newline_suffix"))).to eq(['line.end_with?("bar")'])
    end

    it "rewrites a string-end anchor used with match, whose return value differs" do
      expect(mutated_lines(mutations_for("string_suffix_match"))).to eq(['line.end_with?("bar")'])
    end

    it "unescapes escaped punctuation into the literal" do
      expect(mutated_lines(mutations_for("escaped_literal"))).to eq(['host.end_with?(".example.com")'])
    end

    it "handles a regexp on the left of =~" do
      expect(mutated_lines(mutations_for("regexp_on_the_left"))).to eq(['line.start_with?("foo")'])
    end

    it "handles a regexp receiver of match?" do
      expect(mutated_lines(mutations_for("regexp_receiver_match"))).to eq(['line.start_with?("foo")'])
    end

    it "wraps a compound receiver in parentheses" do
      muts = mutations_from_source("def t(a, b)\n  a + b =~ /^foo/\nend\n")

      expect(mutated_lines(muts)).to eq(['(a + b).start_with?("foo")'])
    end

    it "leaves a method-call operand unwrapped" do
      muts = mutations_from_source("def t(user)\n  user.name =~ /^foo/\nend\n")

      expect(mutated_lines(muts)).to eq(['user.name.start_with?("foo")'])
    end

    it "leaves an index operand unwrapped" do
      muts = mutations_from_source("def t(opts)\n  opts[:k] =~ /^foo/\nend\n")

      expect(mutated_lines(muts)).to eq(['opts[:k].start_with?("foo")'])
    end

    it "wraps a non-call compound operand in parentheses" do
      muts = mutations_from_source("def t(a)\n  \"x\#{a}\" =~ /^foo/\nend\n")

      expect(mutated_lines(muts)).to eq(["(\"x\#{a}\").start_with?(\"foo\")"])
    end

    it "rewrites a match nested in another call's arguments" do
      muts = mutations_from_source("def t(line)\n  log(line =~ /^foo/)\nend\n")

      expect(mutated_lines(muts)).to eq(['log(line.start_with?("foo"))'])
    end

    it "skips other selectors taking a regexp" do
      expect(mutations_from_source("def t(line)\n  line.scan(/^foo/)\nend\n")).to be_empty
    end

    it "skips a regexp receiver called with more than one argument" do
      expect(mutations_from_source("def t(line)\n  /^foo/.match(line, 2)\nend\n")).to be_empty
    end

    it "keeps safe navigation" do
      muts = mutations_from_source("def t(line)\n  line&.match?(/^foo/)\nend\n")

      expect(mutated_lines(muts)).to eq(['line&.start_with?("foo")'])
    end

    it "handles the %r form" do
      muts = mutations_from_source("def t(path)\n  path =~ %r{^/api}\nend\n")

      expect(mutated_lines(muts)).to eq(['path.start_with?("/api")'])
    end

    it "quotes a literal that needs escaping in a string" do
      muts = mutations_from_source("def t(s)\n  s =~ /^\\\"x/\nend\n")

      expect(mutated_lines(muts)).to eq(['s.start_with?("\\"x")'])
    end

    it "skips match? with a string anchor, which is exactly start_with?" do
      expect(mutations_for("exact_predicate_prefix")).to be_empty
    end

    it "skips match? with a string-end anchor, which is exactly end_with?" do
      expect(mutations_for("exact_predicate_suffix")).to be_empty
    end

    it "skips a pattern anchored at both ends" do
      expect(mutations_for("both_anchors")).to be_empty
    end

    it "skips a pattern with a character class escape" do
      expect(mutations_for("character_class")).to be_empty
    end

    it "skips a pattern with a metacharacter" do
      expect(mutations_for("metacharacter")).to be_empty
    end

    it "skips a pattern with flags" do
      expect(mutations_for("with_flag")).to be_empty
    end

    it "skips an unanchored pattern" do
      expect(mutations_for("unanchored")).to be_empty
    end

    it "skips an interpolated pattern" do
      expect(mutations_for("interpolated")).to be_empty
    end

    it "skips match with a position argument" do
      expect(mutations_for("position_argument")).to be_empty
    end

    it "skips an implicit receiver" do
      expect(mutations_for("implicit_receiver")).to be_empty
    end

    it "skips an anchor-only pattern" do
      expect(mutations_from_source("def t(s)\n  s =~ /^/\nend\n")).to be_empty
    end

    it "reads an escaped backslash before z as a literal, not an end anchor" do
      muts = mutations_from_source("def t(s)\n  s =~ /^foo\\\\z/\nend\n")

      expect(mutated_lines(muts)).to eq(['s.start_with?("foo\\\\z")'])
    end

    it "reports the mutation on the line of the match" do
      expect(mutations_for("line_prefix").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("line_prefix").map(&:operator_name).uniq).to eq(["regexp_anchor_to_predicate"])
    end

    it "produces parseable mutations" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#line_prefix") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
