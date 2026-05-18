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

    it "does NOT extend for a plain (non-heredoc) string inside the range" do
      src = 'raise ArgumentError, "plain message"'
      tree = parse(src)
      call = tree.statements.body.first
      args = call.arguments
      original_length = args.location.length

      # A plain StringNode is not a heredoc; its body is inline so no
      # extension is needed even though it sits inside the target range.
      extended = described_class.extend_length(
        node: call, offset: args.location.start_offset, length: original_length
      )

      expect(extended).to eq(original_length)
    end

    it "does NOT extend for a plain string straddling the range boundary" do
      src = 'raise ArgumentError, "a long plain string here"'
      tree = parse(src)
      call = tree.statements.body.first
      string_node = call.arguments.child_nodes.last
      anchor = string_node.opening_loc.start_offset

      # The range opens at the string's opening quote (anchor in range) but
      # ends before its closing quote. Only the heredoc? guard prevents the
      # plain string's far closing offset from extending the span.
      extended = described_class.extend_length(node: call, offset: anchor, length: 4)

      expect(extended).to eq(4)
    end

    it "does NOT extend when a heredoc lives in the node but its anchor is outside the range" do
      src = <<~RUBY
        raise ArgumentError, <<~MSG
          oops
        MSG
      RUBY
      tree = parse(src)
      call = tree.statements.body.first

      # The walked node contains the heredoc, but the target range covers
      # only `raise ` — the anchor at offset 9 sits outside it.
      extended = described_class.extend_length(node: call, offset: 0, length: 6)

      expect(extended).to eq(6)
    end

    it "excludes a heredoc whose anchor sits before the range start" do
      src = <<~RUBY
        raise ArgumentError, <<~MSG
          oops
        MSG
      RUBY
      tree = parse(src)
      call = tree.statements.body.first

      # Anchor is at offset 9; the range starts at 12 (after the anchor).
      extended = described_class.extend_length(node: call, offset: 12, length: 8)

      expect(extended).to eq(8)
    end

    it "excludes a heredoc whose anchor sits after the range end" do
      src = <<~RUBY
        raise ArgumentError, <<~MSG
          oops
        MSG
      RUBY
      tree = parse(src)
      call = tree.statements.body.first

      # Anchor is at offset 9; the range ends at 5 (before the anchor).
      extended = described_class.extend_length(node: call, offset: 0, length: 5)

      expect(extended).to eq(5)
    end

    it "extends an x-string heredoc (`<<~`MARKER``)" do
      src = "run(<<~`CMD`)\n  ls\nCMD\n"
      tree = parse(src)
      call = tree.statements.body.first
      args = call.arguments
      original_length = args.location.length

      extended = described_class.extend_length(
        node: call, offset: args.location.start_offset, length: original_length
      )

      expect(extended).to be > original_length
      end_offset = args.location.start_offset + extended
      expect(src.byteslice(end_offset - 3, 3)).to eq("CMD")
    end

    it "extends an interpolated-string heredoc" do
      src = <<~'RUBY'
        log(<<~MSG)
          value #{x}
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

    it "extends an interpolated-x-string heredoc" do
      src = <<~'RUBY'
        run(<<~`CMD`)
          echo #{x}
        CMD
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
      expect(src.byteslice(end_offset - 3, 3)).to eq("CMD")
    end

    it "descends into an interpolated-string heredoc to reach a nested heredoc" do
      src = <<~'RUBY'
        f(<<~OUTER)
          p #{g(<<~INNER)}
            inner body line
          INNER
        OUTER
      RUBY
      tree = parse(src)
      # Target range covers only the INNER anchor; the OUTER heredoc anchor
      # is out of range. INNER is reachable solely by descending (via super)
      # into the OUTER InterpolatedStringNode.
      inner_anchor = src.index("<<~INNER")
      extended = described_class.extend_length(
        node: tree, offset: inner_anchor, length: "<<~INNER".bytesize
      )

      end_offset = inner_anchor + extended
      expect(extended).to be > "<<~INNER".bytesize
      expect(src.byteslice(end_offset - 5, 5)).to eq("INNER")
    end

    it "descends into an interpolated-x-string heredoc to reach a nested heredoc" do
      src = <<~'RUBY'
        f(<<~`OUTER`)
          echo #{g(<<~INNER)}
            nested line
          INNER
        OUTER
      RUBY
      tree = parse(src)
      inner_anchor = src.index("<<~INNER")
      extended = described_class.extend_length(
        node: tree, offset: inner_anchor, length: "<<~INNER".bytesize
      )

      end_offset = inner_anchor + extended
      expect(extended).to be > "<<~INNER".bytesize
      expect(src.byteslice(end_offset - 5, 5)).to eq("INNER")
    end

    it "finds a heredoc nested inside a deeper enclosing node" do
      src = <<~RUBY
        if condition
          raise ArgumentError, <<~MSG
            deep oops
          MSG
        end
      RUBY
      tree = parse(src)
      call = tree.statements.body.first.statements.body.first
      args = call.arguments
      original_length = args.location.length

      extended = described_class.extend_length(
        node: tree, offset: args.location.start_offset, length: original_length
      )

      expect(extended).to be > original_length
      end_offset = args.location.start_offset + extended
      expect(src.byteslice(end_offset - 3, 3)).to eq("MSG")
    end

    it "preserves the closing offset when the terminator has no trailing newline" do
      src = "raise ArgumentError, <<~MSG\n  oops\nMSG"
      tree = parse(src)
      call = tree.statements.body.first
      args = call.arguments
      original_length = args.location.length

      extended = described_class.extend_length(
        node: call, offset: args.location.start_offset, length: original_length
      )

      # The closing slice "MSG" has no trailing newline, so end_off must NOT
      # be decremented — the span ends exactly at the source end.
      end_offset = args.location.start_offset + extended
      expect(end_offset).to eq(src.bytesize)
      expect(src.byteslice(end_offset - 3, 3)).to eq("MSG")
    end
  end
end
