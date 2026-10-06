# frozen_string_literal: true

require "prism"
require "evilution/ast/literal_callable"

RSpec.describe Evilution::AST::LiteralCallable do
  def expression(code)
    Prism.parse(code).value.statements.body.first
  end

  describe ".body_of" do
    it "returns a `->` lambda itself" do
      expect(described_class.body_of(expression("-> { ready? }"))).to be_a(Prism::LambdaNode)
    end

    it "returns the block of a `lambda` or `proc` call" do
      %w[lambda proc].each do |maker|
        body = described_class.body_of(expression("#{maker} { ready? }"))

        expect(body).to be_a(Prism::BlockNode)
        expect(body.slice).to eq("{ ready? }")
      end
    end

    it "returns nil for anything that is not a literal callable" do
      ["Ready", "method(:ready?)", ":ready?", "lambda(&block)", "Kernel.lambda { 1 }", "build { 1 }", "nil"].each do |code|
        expect(described_class.body_of(expression(code))).to be_nil
      end
    end
  end
end
