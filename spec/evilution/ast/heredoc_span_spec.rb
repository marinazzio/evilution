# frozen_string_literal: true

require "prism"
require "evilution/ast/heredoc_span"

RSpec.describe Evilution::AST::HeredocSpan do
  def parse(src)
    Prism.parse(src).value
  end

  describe ".extend_length" do
    it "returns the original length when node has no heredoc" do
      src = "raise ArgumentError, 'plain message'"
      tree = parse(src)
      length = described_class.extend_length(node: tree, offset: 0, length: src.bytesize)

      expect(length).to eq(src.bytesize)
    end

    it "returns the original length when node is nil" do
      expect(described_class.extend_length(node: nil, offset: 0, length: 10)).to eq(10)
    end

    it "extends to cover heredoc body when anchor falls in the target range" do
      src = <<~RUBY
        raise ArgumentError, <<~MSG
          oops
        MSG
      RUBY
      tree = parse(src)
      call = tree.statements.body.first
      args = call.arguments
      original_length = args.location.length

      extended = described_class.extend_length(
        node: call, offset: args.location.start_offset, length: original_length
      )

      # Extended length should reach past the closing `MSG\n` line so the
      # mutation's replacement covers the body and terminator.
      expect(extended).to be > original_length
      end_offset = args.location.start_offset + extended
      expect(src.byteslice(end_offset - 3, 3)).to eq("MSG")
    end

    it "covers multiple heredocs in the same range and uses the furthest closing" do
      src = <<~RUBY
        Logger.info(<<~A, <<~B)
          first
        A
          second
        B
      RUBY
      tree = parse(src)
      call = tree.statements.body.first
      args = call.arguments
      original_length = args.location.length

      extended = described_class.extend_length(
        node: call, offset: args.location.start_offset, length: original_length
      )

      end_offset = args.location.start_offset + extended
      expect(src.byteslice(end_offset - 1, 1)).to eq("B")
    end

    it "does NOT extend when the heredoc anchor sits outside the target range" do
      src = <<~RUBY
        first(<<~A)
          alpha
        A
        second("plain")
      RUBY
      tree = parse(src)
      stmts = tree.statements.body
      second_call = stmts.last
      original_length = second_call.location.length

      # The second call is `second("plain")` — no heredoc inside. Extension
      # must not pull in the earlier heredoc's body from `first(...)`.
      extended = described_class.extend_length(
        node: second_call,
        offset: second_call.location.start_offset,
        length: original_length
      )

      expect(extended).to eq(original_length)
    end

    it "extends correctly when heredoc is anchored via a chained call (`<<~M.strip`)" do
      src = <<~RUBY
        raise ArgumentError, <<~MSG.strip
          oops
        MSG
      RUBY
      tree = parse(src)
      call = tree.statements.body.first
      args = call.arguments
      original_length = args.location.length

      extended = described_class.extend_length(
        node: call, offset: args.location.start_offset, length: original_length
      )

      expect(extended).to be > original_length
      end_offset = args.location.start_offset + extended
      expect(src.byteslice(end_offset - 3, 3)).to eq("MSG")
    end
  end
end
