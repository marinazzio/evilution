# frozen_string_literal: true

require "prism"
require "evilution/ast/class_body"

RSpec.describe Evilution::AST::ClassBody do
  def anchored(source, line)
    described_class.anchored_at(Prism.parse(source).value, line)
  end

  # The scopes anchored at a line, each by its opening line.
  def headers(source, line)
    anchored(source, line).map { |body| body.node.slice.lines.first.chomp }
  end

  describe ".anchored_at" do
    it "returns the class whose first method starts at the line" do
      source = "class C\n  X = 1\n  def a = 1\n  def b = 2\nend\n"

      expect(headers(source, 3)).to eq(["class C"])
    end

    it "returns nothing for a later method" do
      source = "class C\n  def a = 1\n  def b = 2\nend\n"

      expect(anchored(source, 3)).to eq([])
    end

    it "returns a module" do
      expect(headers("module M\n  def a = 1\nend\n", 2)).to eq(["module M"])
    end

    it "returns a singleton class" do
      source = "class C\n  def a = 1\n  class << self\n    def b = 2\n  end\nend\n"

      expect(headers(source, 4)).to eq(["class << self"])
    end

    it "counts a singleton method as a method of the scope" do
      expect(headers("class C\n  def self.a = 1\nend\n", 2)).to eq(["class C"])
    end

    it "anchors only the innermost scope of a method" do
      source = "module M\n  class C\n    def a = 1\n  end\nend\n"

      expect(headers(source, 3)).to eq(["class C"])
    end

    it "skips a nested class when looking for the first method" do
      source = "class Outer\n  class Inner\n    def i = 1\n  end\n\n  def o = 2\nend\n"

      expect(headers(source, 6)).to eq(["class Outer"])
    end

    it "finds a first method written in a block of the body" do
      source = "module Sized\n  included do\n    def size = 1\n  end\n  def other = 2\nend\n"

      expect(headers(source, 3)).to eq(["module Sized"])
      expect(anchored(source, 5)).to eq([])
    end

    it "does not take a method defined inside another method" do
      source = "class C\n  def a\n    def b = 1\n  end\nend\n"

      expect(anchored(source, 3)).to eq([])
    end

    it "lends a scope without methods the first method of its singleton class" do
      source = "class Report < Base\n  class << self\n    def build = new\n    def other = 1\n  end\nend\n"

      expect(headers(source, 3)).to eq(["class Report < Base", "class << self"])
      expect(anchored(source, 4)).to eq([])
    end

    it "lends through singleton classes that have no method themselves" do
      source = "class C\n  class << self\n  end\n  class << self\n    def a = 1\n  end\nend\n"

      expect(headers(source, 5)).to eq(["class C", "class << self"])
    end

    it "does not lend a singleton class's method to a scope with a method of its own" do
      source = "class C\n  class << self\n    def a = 1\n  end\n  def b = 2\nend\n"

      expect(headers(source, 3)).to eq(["class << self"])
      expect(headers(source, 5)).to eq(["class C"])
    end

    it "does not lend a nested class's method" do
      source = "class Outer\n  class Inner\n    def i = 1\n  end\nend\n"

      expect(headers(source, 3)).to eq(["class Inner"])
    end

    it "does not search the superclass expression" do
      source = "class C < Struct.new(:a) { def x = 1 }\n  def y = 2\nend\n"

      expect(anchored(source, 1)).to eq([])
      expect(headers(source, 2)).to eq(["class C < Struct.new(:a) { def x = 1 }"])
    end

    it "returns nothing for a top-level method" do
      expect(anchored("def a = 1\n", 1)).to eq([])
    end
  end

  describe "#declarations" do
    def declared(source, line)
      anchored(source, line).map do |body|
        body.declarations { |node| node.is_a?(Prism::CallNode) && node.receiver.nil? }.map(&:name)
      end
    end

    it "returns the body nodes the block selects" do
      source = "class C\n  include A\n  X = 1\n  def a = 1\n  extend B\nend\n"

      expect(declared(source, 4)).to eq([%i[include extend]])
    end

    it "searches the blocks of the body" do
      source = "module M\n  def a = 1\n  included do\n    include A\n  end\nend\n"

      expect(declared(source, 2)).to eq([%i[included include]])
    end

    it "leaves method bodies alone" do
      source = "class C\n  def a\n    include A\n  end\nend\n"

      expect(declared(source, 2)).to eq([[]])
    end

    it "leaves nested scopes alone" do
      source = "class C\n  def a = 1\n  class Inner\n    include A\n  end\n  class << self\n    include B\n  end\nend\n"

      expect(declared(source, 2)).to eq([[]])
    end

    it "never offers a method or a nested scope to the block" do
      source = "class C\n  def a = 1\n  class Inner; end\n  class << self; end\n  module M; end\nend\n"
      seen = []
      anchored(source, 2).first.declarations { |node| seen << node.class }

      expect(seen & [Prism::DefNode, Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode]).to eq([])
    end

    # Cutting such a declaration out would leave the modifier dangling.
    it "leaves out a declaration guarded by a modifier" do
      source = "class C\n  def a = 1\n  include A if x\n  include B unless x\n  include D while x\n  include E until x\nend\n"

      expect(declared(source, 2)).to eq([[]])
    end

    it "leaves out the branches of a ternary" do
      source = "class C\n  def a = 1\n  x ? include(A) : include(B)\nend\n"

      expect(declared(source, 2)).to eq([[]])
    end

    it "keeps a declaration in a conditional written out in full" do
      source = "class C\n  def a = 1\n  if x\n    include A\n  else\n    extend B\n  end\nend\n"

      expect(declared(source, 2)).to eq([%i[include extend]])
    end

    it "leaves out a call used as a value" do
      source = "class C\n  def a = 1\n  X = include A\n  register(include(B))\n  include(D) rescue nil\nend\n"

      expect(declared(source, 2)).to eq([[:register]])
    end

    it "searches a body with a rescue clause" do
      source = "class C\n  def a = 1\n  include A\nrescue LoadError\n  include B\nend\n"

      expect(declared(source, 2)).to eq([%i[include include]])
    end

    it "keeps each scope's declarations apart when a method anchors two" do
      source = "class C\n  include A\n  class << self\n    include B\n    def a = 1\n  end\nend\n"

      expect(declared(source, 5)).to eq([[:include], [:include]])
      expect(anchored(source, 5).map { |body| body.declarations { |n| n.is_a?(Prism::CallNode) }.map(&:slice) })
        .to eq([["include A"], ["include B"]])
    end

    it "returns nothing for an empty body" do
      source = "class C\n  class << self\n    def a = 1\n  end\nend\nclass D; end\n"

      expect(declared(source, 3)).to eq([[], []])
    end
  end
end
