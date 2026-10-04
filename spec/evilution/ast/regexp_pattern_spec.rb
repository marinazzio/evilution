# frozen_string_literal: true

require "evilution/ast/regexp_pattern"

RSpec.describe Evilution::AST::RegexpPattern do
  # Parses `source` and returns the pattern of its first regexp literal.
  def pattern_in(source)
    @source = source
    node = find_node(Prism.parse(source).value)
    described_class.parse(node)
  end

  def find_node(root)
    queue = [root]
    while (node = queue.shift)
      return node if node.is_a?(Prism::RegularExpressionNode) || node.is_a?(Prism::InterpolatedRegularExpressionNode)

      queue.concat(node.compact_child_nodes)
    end
  end

  def source_at(start_offset, end_offset)
    @source.byteslice(start_offset, end_offset - start_offset)
  end

  describe ".parse" do
    it "returns nil for an interpolated regexp" do
      expect(pattern_in("x = /a\#{b}c/\n")).to be_nil
    end

    it "returns nil when the pattern cannot be scanned" do
      allow(Regexp::Scanner).to receive(:scan).and_raise(Regexp::Scanner::ScannerError, "boom")

      expect(pattern_in("x = /a/\n")).to be_nil
    end

    it "returns nil for a pattern that is not valid in its encoding" do
      expect(pattern_in((+"x = /a\xFFb/\n").force_encoding(Encoding::UTF_8))).to be_nil
    end

    it "returns nil for a node that is not a regexp" do
      expect(described_class.parse(Prism.parse("x = 1").value)).to be_nil
    end
  end

  describe "#tokens" do
    it "gives each token's offsets in the file" do
      pattern = pattern_in("x = /a\\d+$/\n")

      expect(pattern.tokens.map { |t| [t.type, t.text] }).to eq(
        [[:literal, "a"], [:type, "\\d"], [:quantifier, "+"], [:anchor, "$"]]
      )
      pattern.tokens.each { |token| expect(source_at(token.start_offset, token.end_offset)).to eq(token.text) }
    end

    # regexp_parser counts characters; source surgery needs bytes.
    it "maps offsets to bytes in a multibyte pattern" do
      pattern = pattern_in("x = /é…\\d/\n")
      digit = pattern.tokens.find { |t| t.type == :type }

      expect(source_at(digit.start_offset, digit.end_offset)).to eq("\\d")
      pattern.tokens.each { |token| expect(source_at(token.start_offset, token.end_offset)).to eq(token.text) }
    end

    it "reads whitespace and comments as tokens of their own in extended mode" do
      pattern = pattern_in("x = /a # note\n  b/x\n")

      expect(pattern.tokens.map(&:type)).to eq(%i[literal free_space free_space free_space literal])
      expect(pattern.tokens.find { |t| t.token == :comment }.text).to eq("# note\n")
    end

    it "treats a space as a literal without extended mode" do
      expect(pattern_in("x = /a b/\n").tokens.map(&:type)).to eq(%i[literal])
    end

    it "handles percent-r literals and escaped delimiters" do
      expect(pattern_in("x = %r{a/b}\n").tokens.map(&:text)).to eq(["a/b"])

      pattern = pattern_in("x = /a\\/b/\n")
      expect(pattern.tokens.map(&:text)).to eq(["a", "\\/", "b"])
      pattern.tokens.each { |token| expect(source_at(token.start_offset, token.end_offset)).to eq(token.text) }
    end
  end

  describe "#each_expression" do
    it "yields each expression with its offsets in the file" do
      pattern = pattern_in("x = /é(ab|c)/\n")
      ranges = []
      pattern.each_expression { |expression, start_offset, end_offset| ranges << [expression.class, start_offset, end_offset] }

      group = ranges.find { |klass, *| klass == Regexp::Expression::Group::Capture }
      expect(source_at(group[1], group[2])).to eq("(ab|c)")
      alternatives = ranges.select { |klass, *| klass == Regexp::Expression::Alternative }
      expect(alternatives.map { |_, s, e| source_at(s, e) }).to eq(%w[ab c])
    end
  end

  describe "#compiles?" do
    it "accepts an edit that leaves a valid pattern" do
      source = "x = /a\\d/\n"
      pattern = pattern_in(source)
      start_offset = source.index("\\d")

      expect(pattern.compiles?(start_offset, start_offset + 2, "\\D")).to be(true)
    end

    # Prism accepts a pattern whose backreference points at a group that no
    # longer exists; only compiling it shows the mutant cannot load.
    it "rejects an edit that breaks a reference inside the pattern" do
      source = "x = /(a)\\1/\n"
      pattern = pattern_in(source)
      start_offset = source.index("(")

      expect(pattern.compiles?(start_offset, start_offset + 1, "(?:")).to be(false)
    end

    # Replacing a span with itself must give back the original pattern, so a
    # prefix or suffix lost in the splice shows up as a pattern that no longer
    # compiles.
    it "splices the replacement between the untouched prefix and suffix" do
      source = "x = /x(a)b/\n"
      pattern = pattern_in(source)
      start_offset = source.index("a)")

      expect(pattern.compiles?(start_offset, start_offset + 1, "a")).to be(true)
      expect(pattern.compiles?(start_offset, start_offset + 1, "(")).to be(false)
    end

    it "compiles with the literal's own flags" do
      source = "x = /a # )\n/x\n"
      pattern = pattern_in(source)
      start_offset = source.index("a")

      expect(pattern.compiles?(start_offset, start_offset + 1, "b")).to be(true)
    end

    it "does not print the warnings Onigmo raises for odd patterns" do
      source = "x = /[ab]/\n"
      pattern = pattern_in(source)
      start_offset = source.index("b")

      original = $VERBOSE
      $VERBOSE = true
      expect { pattern.compiles?(start_offset, start_offset + 1, "a") }.not_to output.to_stderr
      expect($VERBOSE).to be(true)
    ensure
      $VERBOSE = original
    end
  end
end
