# frozen_string_literal: true

require "prism"
require "evilution/ast/def_region"

RSpec.describe Evilution::AST::DefRegion do
  def def_node(source, name = :total)
    finder = Class.new(Prism::Visitor) do
      attr_reader :found

      define_method(:visit_def_node) do |node|
        @found ||= node if node.name == name
        super(node)
      end
    end.new
    Prism.parse(source).value.accept(finder)
    finder.found
  end

  def region(source, name = :total, **options)
    described_class.new(source, def_node(source, name), **options)
  end

  # The mutation that replaces the first `from` in the source with `to`.
  def parse(source, from, to, name = :total, **options)
    offset = source.b.index(from.b)
    region(source, name, **options).parse(offset: offset, length: from.bytesize, replacement: to)
  end

  let(:source) do
    <<~RUBY
      class Cart
        LIMIT = 10

        def total(items)
          items.sum { |item| item.price } * 2
        end

        def count = 1
      end
    RUBY
  end

  describe "#parse" do
    it "is the mutated def when the def parses on its own" do
      region = parse(source, "* 2", "* 3")

      expect(region.node).to be_a(Prism::DefNode)
      expect(region.node.slice).to eq("def total(items)\n    items.sum { |item| item.price } * 3\n  end")
    end

    it "tells where the original def is and what the mutation was" do
      region = parse(source, "* 2", "* 3")
      start = source.index("def total")

      expect(region).to have_attributes(span: start..(source.index("end\n\n") + 3),
                                        offset: source.index("* 2"), length: 3, replacement: "* 3")
    end

    it "keeps the columns of the def's first line" do
      region = parse(source, "* 2", "* 3")

      expect(region.source).to start_with("  def total")
      expect(region.node.location.start_column).to eq(2)
    end

    it "is nil when the mutated def does not parse" do
      expect(parse(source, "* 2", "* ")).to be_nil
    end

    it "is nil when the mutation closes the def and opens another" do
      expect(parse(source, " * 2", "\n  end\n  def other\n    1")).to be_nil
    end

    it "is nil when the mutation reaches outside the def" do
      expect(parse(source, "LIMIT = 10", "LIMIT = 11")).to be_nil
    end

    it "is nil when the mutation runs past the end of the def" do
      expect(parse(source, "  end\n\n  def count", "  end\n  def count")).to be_nil
    end

    it "is nil for an endless def, whose end the text after it decides" do
      expect(parse(source, "count = 1", "count = 2", :count)).to be_nil
    end

    it "takes a def on self" do
      code = "class A\n  def self.total\n    1\n  end\nend\n"

      expect(parse(code, "1", "2")).not_to be_nil
    end

    it "is nil for a def on another receiver, which reads names from the scope around it" do
      code = "obj = Object.new\ndef obj.total\n  1\nend\n"

      expect(parse(code, "  1", "  2")).to be_nil
    end

    it "takes a def handed to a visibility call on its line" do
      code = "class A\n  private def total\n    1\n  end\nend\n"

      expect(parse(code, "    1", "    2").source).to start_with("          def total")
    end

    it "is nil when the def's line holds more than names before it" do
      code = "class A\n  x = def total\n    1\n  end\nend\n"

      expect(parse(code, "    1", "    2")).to be_nil
    end

    it "is nil when the def's line opens a heredoc before it" do
      code = "class A\n  foo(<<~TXT, def total\n    body\n  TXT\n    1\n  end)\nend\n"

      expect(parse(code, "    1", "    2")).to be_nil
    end

    it "is nil when a heredoc opened on the def's last line has its body after the def" do
      code = "class A\n  def total\n    x(<<~TXT) end\n    body\n  TXT\nend\n"

      expect(parse(code, "x(", "y(")).to be_nil
    end

    it "is nil in a file that names its encoding" do
      code = "# encoding: us-ascii\nclass A\n  def total\n    \"a\"\n  end\nend\n"

      expect(parse(code, "\"a\"", "\"é\"")).to be_nil
    end

    it "is nil in a file whose second line names its encoding" do
      code = "#!/usr/bin/env ruby\n# -*- coding: us-ascii -*-\ndef total\n  1\nend\n"

      expect(parse(code, "  1", "  2")).to be_nil
    end

    it "is nil when the def is not where the source has it" do
      other = "def total\n  1\nend\n"
      region = described_class.new("x = 1\n#{other}", def_node(other))

      expect(region.parse(offset: 12, length: 1, replacement: "2")).to be_nil
    end

    it "is nil when the node is another def than the one at its offsets in the source" do
      other = "def total\n  1\nend\n"
      region = described_class.new("def total\n  2\nend\n", def_node(other))

      expect(region.parse(offset: 12, length: 1, replacement: "3")).to be_nil
    end

    it "takes a mutation of the whole def" do
      code = "def total\n  1\nend\n"

      expect(parse(code, "def total\n  1\nend", "def total\n  2\nend").node.slice).to eq("def total\n  2\nend")
    end

    it "is nil when the mutation makes the def endless" do
      code = "def total\n  1\nend\n"

      expect(parse(code, "def total\n  1\nend", "def total = 2")).to be_nil
    end

    it "is nil when the mutation gives the def another receiver" do
      code = "def total\n  1\nend\n"

      expect(parse(code, "def total", "def obj.total")).to be_nil
    end

    it "is nil when the mutation makes the def part of a larger expression" do
      code = "def total\n  1\nend\n"

      expect(parse(code, "end", "end.itself")).to be_nil
    end

    it "is nil when the mutation moves the def off its line" do
      code = "def total\n  1\nend\n"

      expect(parse(code, "def", "\ndef")).to be_nil
    end

    it "is nil when the mutation leaves text after the def" do
      code = "def total\n  1\nend\n"

      expect(parse(code, "end", "end\n")).to be_nil
    end

    it "takes a file of one line with no line break" do
      expect(parse("def total; 1; end", "1", "2")).not_to be_nil
    end

    it "takes a file that mentions an encoding past its second line" do
      code = "class A\n  X = 1\n  def total\n    encoding\n  end\nend\n"

      expect(parse(code, "encoding", "coding")).not_to be_nil
    end

    it "takes a def after multibyte text, handed to a visibility call" do
      code = "# héllo wörld\nclass A\n  private def total\n    1\n  end\nend\n"

      expect(parse(code, "    1", "    2").source).to start_with("          def total")
    end

    it "splices a multibyte replacement into a def holding multibyte text" do
      code = "def total\n  \"ä\" + \"b\"\nend\n"

      expect(parse(code, "\"b\"", "\"ü\"").node.slice).to eq("def total\n  \"ä\" + \"ü\"\nend")
    end

    it "keeps the source's encoding" do
      code = "def total\n  \"é\"\nend\n"

      expect(parse(code, "é", "ü").source.encoding).to eq(Encoding::UTF_8)
    end

    it "asks parse.y as well on an interpreter that compiles with it" do
      code = "def total(v)\n  return unless v in nil[size: [first]]\n  first\nend\n"

      expect(parse(code, "first\nend", "first + 1\nend", prism_interpreter: true)).not_to be_nil
      expect(parse(code, "first\nend", "first + 1\nend", prism_interpreter: false)).to be_nil
    end

    it "takes a mutated def parse.y accepts too on an interpreter that compiles with it" do
      expect(parse(source, "* 2", "* 3", prism_interpreter: false)).not_to be_nil
    end

    it "is nil in a file whose second line names its encoding after a first line of multibyte text" do
      code = "#!/usr/bin/env ruby #{"é" * 40}\n# coding: us-ascii\ndef total\n  1\nend\n"

      expect(parse(code, "  1", "  2")).to be_nil
    end

    it "takes the interpreter's parser from SyntaxCheck by default" do
      code = "def total(v)\n  return unless v in nil[size: [first]]\n  first\nend\n"

      expect(parse(code, "first\nend", "first + 1\nend").nil?).to eq(!Evilution::AST::SyntaxCheck::PRISM_INTERPRETER)
    end
  end

  it "takes no node other than a def" do
    code = "scope :open, -> { 1 }\n"
    lambda_node = Prism.parse(code).value.statements.body.first.arguments.arguments.last

    expect(described_class.new(code, lambda_node).parse(offset: code.index("1"), length: 1, replacement: "2")).to be_nil
  end

  it "takes no def at all" do
    expect(described_class.new("x = 1\n", nil).parse(offset: 0, length: 1, replacement: "y")).to be_nil
  end
end
