# frozen_string_literal: true

RSpec.describe Evilution::AST::SourceSurgeon do
  describe ".apply" do
    it "replaces text at the given byte offset" do
      source = "age >= 18"
      result = described_class.apply(source, offset: 4, length: 2, replacement: ">")

      expect(result).to eq("age > 18")
    end

    it "handles replacement shorter than original" do
      source = "x == y"
      result = described_class.apply(source, offset: 2, length: 2, replacement: ">")

      expect(result).to eq("x > y")
    end

    it "handles replacement longer than original" do
      source = "x > y"
      result = described_class.apply(source, offset: 2, length: 1, replacement: ">=")

      expect(result).to eq("x >= y")
    end

    it "handles replacement at start of string" do
      source = "true && false"
      result = described_class.apply(source, offset: 0, length: 4, replacement: "false")

      expect(result).to eq("false && false")
    end

    it "handles replacement at end of string" do
      source = "x + 42"
      result = described_class.apply(source, offset: 4, length: 2, replacement: "0")

      expect(result).to eq("x + 0")
    end

    it "does not mutate the original string" do
      source = "age >= 18"
      described_class.apply(source, offset: 4, length: 2, replacement: ">")

      expect(source).to eq("age >= 18")
    end

    it "handles multi-line source" do
      source = "def foo\n  x >= 10\nend"
      result = described_class.apply(source, offset: 12, length: 2, replacement: ">")

      expect(result).to eq("def foo\n  x > 10\nend")
    end

    it "handles replacing with empty string" do
      source = "return 42"
      result = described_class.apply(source, offset: 6, length: 3, replacement: "")

      expect(result).to eq("return")
    end

    context "with multi-byte UTF-8 characters" do
      it "replaces at correct byte offset after Cyrillic characters" do
        source = 'name = "Подкаст"'
        # "Подкаст" is 7 chars but 14 bytes; byte offset of closing quote is 22
        # Byte layout: name = " (8 bytes) + Подкаст (14 bytes) + " (1 byte) = 23 bytes
        # Replace the whole string literal including quotes (byte offset 7, length 16)
        result = described_class.apply(source, offset: 7, length: 16, replacement: '"replaced"')

        expect(result).to eq('name = "replaced"')
      end

      it "replaces operator after Cyrillic string literal" do
        source = "x = \"Привет\"\ny = 1 + 2"
        # "Привет" = 6 chars, 12 bytes
        # Line 2: y = 1 + 2 → the + is at byte offset 25
        result = described_class.apply(source, offset: 25, length: 1, replacement: "-")

        expect(result).to eq("x = \"Привет\"\ny = 1 - 2")
      end

      it "handles emoji characters in source" do
        source = "label = \"🎉🎊\"\ncount = 42"
        # 🎉 and 🎊 are 4 bytes each
        # count = 42 → "42" starts at byte offset 27
        result = described_class.apply(source, offset: 27, length: 2, replacement: "0")

        expect(result).to eq("label = \"🎉🎊\"\ncount = 0")
      end

      it "handles CJK characters in source" do
        source = "msg = \"日本語\"\nx >= 10"
        # 日本語 = 3 chars, 9 bytes
        # msg = " (7 bytes) + 日本語 (9 bytes) + " (1 byte) + \n (1 byte) = 18 bytes
        # x >= 10 → >= starts at byte offset 20
        result = described_class.apply(source, offset: 20, length: 2, replacement: ">")

        expect(result).to eq("msg = \"日本語\"\nx > 10")
      end

      it "preserves original encoding" do
        source = "x = \"Тест\"\ny = 1 + 2"
        result = described_class.apply(source, offset: 0, length: 1, replacement: "z")

        expect(result.encoding).to eq(source.encoding)
      end

      it "works with Prism byte offsets end-to-end" do
        source = "def foo\n  title = \"Подкаст клуба\"\n  x = 1 + 2\nend"
        tree = Prism.parse(source).value

        # Find the + operator node
        call_nodes = []
        visitor = Class.new(Prism::Visitor) do
          define_method(:visit_call_node) do |node|
            call_nodes << node if node.name == :+
            super(node)
          end
        end
        visitor.new.visit(tree)

        plus_node = call_nodes.first
        loc = plus_node.message_loc
        result = described_class.apply(source, offset: loc.start_offset, length: loc.length, replacement: "-")

        expect(result).to include("x = 1 - 2")
        expect(result).to include("Подкаст клуба")
        expect(Prism.parse(result).errors).to be_empty
      end
    end
  end
end
