# frozen_string_literal: true

require "evilution/ast/constant_names"

RSpec.describe Evilution::AST::ConstantNames do
  subject(:extractor) { described_class.new }

  describe "#call" do
    it "returns an empty array for empty source" do
      expect(extractor.call("")).to eq([])
    end

    it "returns top-level module names" do
      expect(extractor.call("module Foo; end\n")).to eq(["Foo"])
    end

    it "returns top-level class names" do
      expect(extractor.call("class Foo; end\n")).to eq(["Foo"])
    end

    it "returns nested class names fully qualified" do
      source = <<~RUBY
        module Foo
          class Bar
          end
        end
      RUBY

      expect(extractor.call(source)).to eq(%w[Foo Foo::Bar])
    end

    it "preserves fully-qualified compact names" do
      expect(extractor.call("module Foo::Bar; end\n")).to eq(["Foo::Bar"])
    end

    it "returns multiple top-level siblings" do
      source = "module A; end\nclass B; end\n"

      expect(extractor.call(source)).to eq(%w[A B])
    end

    it "returns an empty array for source with only methods / no constant declarations" do
      expect(extractor.call("def foo; end\n")).to eq([])
    end

    it "returns an empty array for source that fails to parse" do
      expect(extractor.call("class Foo; def bar")).to eq([])
    end
  end
end
