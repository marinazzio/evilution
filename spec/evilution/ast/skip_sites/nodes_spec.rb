# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_sites/nodes"

RSpec.describe Evilution::AST::SkipSites::Nodes do
  def expression(code)
    Prism.parse(code).value.statements.body.first
  end

  describe ".same?" do
    let(:source) { "foo(a, ab)\n" }
    let(:arguments) { expression(source).arguments.arguments }

    it "holds for a node parsed again from the same source" do
      expect(described_class.same?(arguments.first, expression(source).arguments.arguments.first)).to be true
    end

    it "fails for nodes at another offset" do
      expect(described_class.same?(arguments.first, expression("foo(b, ab)\n").arguments.arguments.last)).to be false
    end

    it "fails for nodes of another length at the same offset" do
      expect(described_class.same?(arguments.last, expression("foo(a, a)\n").arguments.arguments.last)).to be false
    end

    it "fails for nodes of another type over the same bytes" do
      expect(described_class.same?(expression("x\n"), Prism.parse("x\n").value.statements)).to be false
    end
  end

  describe ".kernel_call?" do
    it "holds for a named call without a receiver" do
      expect(described_class.kernel_call?(expression("raise 'x'"), %i[raise])).to be true
    end

    it "holds for a named call sent to Kernel or ::Kernel" do
      expect(described_class.kernel_call?(expression("Kernel.raise 'x'"), %i[raise])).to be true
      expect(described_class.kernel_call?(expression("::Kernel.raise 'x'"), %i[raise])).to be true
    end

    it "fails for another name" do
      expect(described_class.kernel_call?(expression("fail 'x'"), %i[raise])).to be false
    end

    it "fails for a call sent to another receiver" do
      expect(described_class.kernel_call?(expression("Thread.raise 'x'"), %i[raise])).to be false
      expect(described_class.kernel_call?(expression("kernel.raise 'x'"), %i[raise])).to be false
    end

    it "fails for a node that is not a call" do
      expect(described_class.kernel_call?(expression("raise = 1"), %i[raise])).to be false
    end
  end

  describe ".constant_named?" do
    it "holds for a constant or a constant path of the name" do
      expect(described_class.constant_named?(expression("Kernel"), :Kernel)).to be true
      expect(described_class.constant_named?(expression("::Kernel"), :Kernel)).to be true
    end

    it "fails for another name" do
      expect(described_class.constant_named?(expression("Object"), :Kernel)).to be false
      expect(described_class.constant_named?(expression("A::Object"), :Kernel)).to be false
    end

    it "fails for a method of the name" do
      expect(described_class.constant_named?(expression("Kernel()"), :Kernel)).to be false
    end
  end

  describe ".receiver_name" do
    {
      "logger" => "logger", "@logger" => "logger", "@@logger" => "logger", "$logger" => "logger",
      "LOGGER" => "LOGGER", "App::LOGGER" => "LOGGER", "Rails.logger" => "logger"
    }.each do |code, name|
      it "names #{code} #{name}" do
        expect(described_class.receiver_name(expression(code))).to eq(name)
      end
    end

    it "names a local variable" do
      expect(described_class.receiver_name(Prism.parse("logger = 1\nlogger\n").value.statements.body.last))
        .to eq("logger")
    end

    it "names no call that takes arguments or a block" do
      expect(described_class.receiver_name(expression("logger(1)"))).to be_nil
      expect(described_class.receiver_name(expression("logger { 1 }"))).to be_nil
      expect(described_class.receiver_name(expression("logger(&blk)"))).to be_nil
    end

    it "names no literal" do
      expect(described_class.receiver_name(expression("'logger'"))).to be_nil
    end
  end

  describe ".positional_arguments" do
    it "is empty for a call without arguments" do
      expect(described_class.positional_arguments(expression("raise"))).to eq([])
    end

    it "leaves out keywords" do
      expect(described_class.positional_arguments(expression("f(a, 'b', c: 1)")).map(&:slice)).to eq(["a", "'b'"])
    end

    it "is nil when a splat makes the positions unknown" do
      expect(described_class.positional_arguments(expression("f(a, *b)"))).to be_nil
    end

    it "is nil when arguments are forwarded" do
      call = Prism.parse("def g(...)\n  f(a, ...)\nend\n").value.statements.body.first.body.body.first

      expect(described_class.positional_arguments(call)).to be_nil
    end
  end

  describe ".string?" do
    it "holds for plain and interpolated strings" do
      expect(described_class.string?(expression("'a'"))).to be true
      expect(described_class.string?(expression("\"a\#{b}\""))).to be true
    end

    it "fails for other literals" do
      expect(described_class.string?(expression(":a"))).to be false
    end
  end
end
