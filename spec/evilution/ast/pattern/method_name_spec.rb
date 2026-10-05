# frozen_string_literal: true

require "evilution/ast/pattern/method_name"

RSpec.describe Evilution::AST::Pattern::MethodName do
  describe ".scan" do
    it "reads an identifier and returns the position after it" do
      expect(described_class.scan("name=log}", 5)).to eq(["log", 8])
    end

    it "reads an identifier with a trailing ?, ! or =" do
      expect(described_class.scan("valid?|x", 0)).to eq(["valid?", 6])
      expect(described_class.scan("save!}", 0)).to eq(["save!", 5])
      expect(described_class.scan("value=}", 0)).to eq(["value=", 6])
    end

    it "takes one suffix at most" do
      expect(described_class.scan("foo?!", 0)).to eq(["foo?", 4])
    end

    it "reads every bare operator" do
      described_class::OPERATORS.each do |operator|
        expect(described_class.scan("#{operator}}", 0)).to eq([operator, operator.length])
      end
    end

    it "prefers the longest operator" do
      expect(described_class.scan("<=>}", 0)).to eq(["<=>", 3])
      expect(described_class.scan("===}", 0)).to eq(["===", 3])
      expect(described_class.scan("[]=}", 0)).to eq(["[]=", 3])
    end

    it "reads a quoted name without its quotes" do
      expect(described_class.scan("x='|'}", 2)).to eq(["|", 5])
      expect(described_class.scan('x="!="}', 2)).to eq(["!=", 6])
    end

    it "ends a quoted name at the same kind of quote" do
      expect(described_class.scan(%q('a"b'}), 0)).to eq(['a"b', 5])
    end

    it "raises at the end of the input" do
      expect { described_class.scan("name=", 5) }.to raise_error(
        Evilution::ConfigError, "unexpected end of pattern at position 5"
      )
    end

    it "raises on an unterminated quoted name" do
      expect { described_class.scan("x='<=>", 2) }.to raise_error(
        Evilution::ConfigError, "unterminated quoted name starting at position 2"
      )
    end

    it "raises on an empty quoted name" do
      expect { described_class.scan("x=''", 2) }.to raise_error(
        Evilution::ConfigError, "empty quoted name at position 2"
      )
    end

    it "raises on a name it cannot read, suggesting quotes" do
      expect { described_class.scan("x=`", 2) }.to raise_error(
        Evilution::ConfigError,
        "invalid name starting with '`' at position 2; " \
        "quote names that are not identifiers or operators, e.g. name='|'"
      )
      expect { described_class.scan("9a", 0) }.to raise_error(Evilution::ConfigError, /invalid name starting with '9'/)
    end
  end
end
