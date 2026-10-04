# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RegexpCaptureToPassive do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["regexp_capture_to_passive", ".rb"])
    tmpfile.write("def probe(s)\n#{body}end\n")
    tmpfile.flush
    described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  def mutated_lines(body, filter: nil)
    mutations_for(body, filter: filter).map { |m| m.mutated_source.lines[m.line - 1].strip }
  end

  describe "#call" do
    it "turns a capture group into a passive group" do
      expect(mutated_lines("  s[/id=(\\d+)/, 1]\n")).to eq(["s[/id=(?:\\d+)/, 1]"])
    end

    it "turns each capture group into a passive group separately" do
      expect(mutated_lines("  s.match(/(\\w+)@(\\w+)/)\n")).to eq(
        ["s.match(/(?:\\w+)@(\\w+)/)", "s.match(/(\\w+)@(?:\\w+)/)"]
      )
    end

    it "turns a nested capture group into a passive group" do
      expect(mutated_lines("  s.scan(/((a)b)/)\n")).to eq(["s.scan(/(?:(a)b)/)", "s.scan(/((?:a)b)/)"])
    end

    # match? and !~ never expose captures, so the swap could change nothing.
    it "leaves a pattern passed to match? or !~ alone" do
      expect(mutated_lines("  s.match?(/(a|b)c/)\n")).to be_empty
      expect(mutated_lines("  /(a|b)c/.match?(s)\n")).to be_empty
      expect(mutated_lines("  s !~ /(a|b)c/\n")).to be_empty
    end

    it "tells apart identical patterns passed to match? and to match" do
      expect(mutated_lines("  s.match?(/(a)b/)\n  s.match(/(a)b/)\n")).to eq(["s.match(/(?:a)b/)"])
    end

    it "handles match? called without arguments" do
      expect(mutated_lines("  s.match?\n  s.match(/(a)b/)\n")).to eq(["s.match(/(?:a)b/)"])
    end

    it "still mutates a pattern used with =~, match or a case" do
      expect(mutated_lines("  s =~ /(a)b/\n")).to eq(["s =~ /(?:a)b/"])
      expect(mutated_lines("  s.match(/(a)b/)\n")).to eq(["s.match(/(?:a)b/)"])
      expect(mutated_lines("  case s\n  when /(a)b/ then $1\n  end\n")).to eq(["when /(?:a)b/ then $1"])
    end

    # With a named group present Ruby keeps only named captures, so a plain
    # group captures nothing to begin with.
    it "leaves a pattern with named groups alone" do
      expect(mutated_lines("  s.match(/(?<user>\\w+)@(\\w+)/)\n")).to be_empty
    end

    # A passive group renumbers the groups after it, so a numbered reference
    # would quietly point at a different group.
    it "leaves a pattern with numbered references alone" do
      expect(mutated_lines("  s.match(/(a)(b)(c)\\2/)\n")).to be_empty
      expect(mutated_lines("  s.match(/(a)(b)\\2/)\n")).to be_empty
      expect(mutated_lines("  s.match(/(a)\\k<1>/)\n")).to be_empty
      expect(mutated_lines("  s.match(/(a)\\g<1>/)\n")).to be_empty
      expect(mutated_lines("  s.match(/(a)\\k<-1>/)\n")).to be_empty
    end

    it "leaves other groups alone" do
      expect(mutated_lines("  s.match(/(?:a)(?=b)(?!c)(?<=d)(?>e)(?i:f)/)\n")).to be_empty
    end

    it "leaves parentheses that are not groups alone" do
      expect(mutated_lines("  s.match(/[()]\\(\\)/)\n")).to be_empty
      expect(mutated_lines("  s.match(/a # (b)\n/x)\n")).to be_empty
    end

    it "keeps the literal's delimiters, flags and multibyte text" do
      expect(mutated_lines("  s[%r{é(…)/}i, 1]\n")).to eq(["s[%r{é(?:…)/}i, 1]"])
    end

    it "emits nothing for a pattern regexp_parser cannot read" do
      allow(Evilution::AST::RegexpPattern).to receive(:parse).and_return(nil)

      expect(mutated_lines("  s.match(/(a)/)\n")).to be_empty
    end

    it "leaves interpolated patterns alone" do
      expect(mutated_lines("  s.match(/(\#{s})/)\n")).to be_empty
    end

    it "produces parseable mutations" do
      tmpfile = Tempfile.new(["regexp_capture_to_passive", ".rb"])
      tmpfile.write("def probe(s)\n  s.scan(/((a)b)(c)/)\nend\n")
      tmpfile.flush
      muts = described_class.new.call(Evilution::AST::Parser.new.call(tmpfile.path).first)

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
      expect(muts.map(&:operator_name).uniq).to eq(["regexp_capture_to_passive"])
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["regular_expression"])

      expect(mutated_lines("  s.match(/(a)/)\n", filter: filter)).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
