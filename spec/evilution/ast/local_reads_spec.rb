# frozen_string_literal: true

RSpec.describe Evilution::AST::LocalReads do
  subject(:local_reads) { described_class.new }

  # The scan works on a scope body, which is what an operator holds when it is
  # deciding whether a parameter it is about to change is ever read.
  def body_of(source)
    Prism.parse(source).value.breadth_first_search { |n| n.is_a?(Prism::DefNode) || n.is_a?(Prism::BlockNode) }.body
  end

  describe "#call" do
    it "finds a read in the scope body" do
      body = body_of("def m(value)\n  touch(value)\nend\n")

      expect(local_reads.call(body, "value")).to be(true)
    end

    it "is false when the name is never read" do
      body = body_of("def m(value)\n  touch\nend\n")

      expect(local_reads.call(body, "value")).to be(false)
    end

    it "is false for a different name" do
      body = body_of("def m(value)\n  touch(other)\nend\n")

      expect(local_reads.call(body, "value")).to be(false)
    end

    # A block shares the scope it is written in, so the read still counts.
    it "finds a read inside a nested block" do
      body = body_of("def m(value)\n  items.each { |i| touch(value, i) }\nend\n")

      expect(local_reads.call(body, "value")).to be(true)
    end

    # A block parameter of the same name shadows the outer local, so reads
    # inside that block are reads of the block's own variable.
    it "ignores a read shadowed by a block parameter of the same name" do
      body = body_of("def m(value)\n  items.each { |value| touch(value) }\nend\n")

      expect(local_reads.call(body, "value")).to be(false)
    end

    it "ignores a read shadowed by a block-local variable of the same name" do
      body = body_of("def m(value)\n  items.each { |i; value| value = i; touch(value) }\nend\n")

      expect(local_reads.call(body, "value")).to be(false)
    end

    # A lambda is a scope in the same way a block is.
    it "finds a read inside a lambda" do
      body = body_of("def m(value)\n  handler = ->(i) { touch(value, i) }\n  handler\nend\n")

      expect(local_reads.call(body, "value")).to be(true)
    end

    it "ignores a read shadowed by a lambda parameter of the same name" do
      body = body_of("def m(value)\n  handler = ->(value) { touch(value) }\n  handler\nend\n")

      expect(local_reads.call(body, "value")).to be(false)
    end

    it "finds a read in a block nested two deep" do
      body = body_of("def m(value)\n  items.each { |i| others.each { |j| touch(value) } }\nend\n")

      expect(local_reads.call(body, "value")).to be(true)
    end

    # Only the shadowing block is excluded; a sibling block still reads the
    # outer local.
    it "finds a read in a sibling of a shadowing block" do
      body = body_of("def m(value)\n  items.each { |value| touch(value) }\n  others.each { |j| touch(value) }\nend\n")

      expect(local_reads.call(body, "value")).to be(true)
    end

    # A nested def opens its own scope, so a local of the same name in there is
    # a different variable.
    it "ignores a local of the same name inside a nested def" do
      body = body_of("def m(value)\n  def inner\n    value = 1\n    value\n  end\nend\n")

      expect(local_reads.call(body, "value")).to be(false)
    end

    it "finds a read that follows a nested def" do
      body = body_of("def m(value)\n  def inner\n    1\n  end\n  touch(value)\nend\n")

      expect(local_reads.call(body, "value")).to be(true)
    end

    it "finds a read in a later statement" do
      body = body_of("def m(value)\n  touch\n  touch(value)\nend\n")

      expect(local_reads.call(body, "value")).to be(true)
    end

    it "is false for a nil body" do
      expect(local_reads.call(nil, "value")).to be(false)
    end

    # A write on its own is not a read.
    it "is false when the name is only written" do
      body = body_of("def m(value)\n  value = 1\n  touch\nend\n")

      expect(local_reads.call(body, "value")).to be(false)
    end
  end
end
