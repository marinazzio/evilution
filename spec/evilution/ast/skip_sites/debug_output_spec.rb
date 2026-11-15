# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_sites/debug_output"
require_relative "../../../support/skip_site_helpers"

RSpec.describe Evilution::AST::SkipSites::DebugOutput do
  include SkipSiteHelpers

  it "is named debug_output" do
    expect(described_class.new.name).to eq(:debug_output)
  end

  %w[puts print warn printf Kernel.puts $stdout.puts $stderr.print $stdout.printf STDOUT.write STDERR.puts].each do |call|
    it "covers the output of #{call}" do
      expect(covered?("#{call}(\"done\")\n", "\"done\"", Prism::StringNode)).to be true
    end
  end

  it "covers the call itself, so deleting it is skipped" do
    expect(covered?("def f\n  puts \"done\"\n  1\nend\n", "puts \"done\"", Prism::CallNode)).to be true
  end

  it "leaves output sent to another stream" do
    expect(covered?("io.puts(\"done\")\n", "\"done\"", Prism::StringNode)).to be false
    expect(covered?("$log.puts(\"done\")\n", "\"done\"", Prism::StringNode)).to be false
  end

  it "leaves a method named like a stream that is not a global or a constant" do
    expect(covered?("config.stdout.puts(\"done\")\n", "\"done\"", Prism::StringNode)).to be false
  end

  it "leaves a stream's other methods" do
    expect(covered?("$stdout.sync(\"done\")\n", "\"done\"", Prism::StringNode)).to be false
  end

  it "leaves a writer sent to no receiver" do
    expect(covered?("write(\"done\")\n", "\"done\"", Prism::StringNode)).to be false
  end

  it "covers a bare puts, which prints only a newline" do
    expect(covered?("def f\n  puts\n  1\nend\n", "puts", Prism::CallNode)).to be true
  end

  it "leaves a statement that does not print, whose value is dropped all the same" do
    expect(covered?("def f(x)\n  save(x)\n  x\nend\n", "save(x)", Prism::CallNode)).to be false
  end

  context "with p and pp, which return what they print" do
    it "covers a statement whose value is discarded" do
      source = "def f(x)\n  p x\n  x + 1\nend\n"

      expect(covered?(source, "p x", Prism::CallNode)).to be true
      expect(covered?(source, "x", Prism::LocalVariableReadNode, nth: 0)).to be true
    end

    it "covers pp the same way" do
      expect(covered?("def f(x)\n  pp x\n  x\nend\n", "pp x", Prism::CallNode)).to be true
    end

    it "leaves the last statement of a method, whose value is returned" do
      expect(covered?("def f(x)\n  p x\nend\n", "p x", Prism::CallNode)).to be false
    end

    it "leaves a value that is used" do
      expect(covered?("y = p(x)\n", "p(x)", Prism::CallNode)).to be false
    end

    it "leaves an argument of another call" do
      expect(covered?("total(p(x))\nnil\n", "p(x)", Prism::CallNode)).to be false
    end
  end

  context "when the value of the output is used" do
    it "leaves the call itself, whose value would change" do
      expect(covered?("puts(x) || x.save\nnil\n", "puts(x)", Prism::CallNode)).to be false
      expect(covered?("def f(x)\n  puts x.summary\nend\n", "puts x.summary", Prism::CallNode)).to be false
    end

    it "still covers the literal text of a printer that returns nil" do
      expect(covered?("def f\n  puts \"done\"\nend\n", "\"done\"", Prism::StringNode)).to be true
    end

    it "leaves a stream write, which returns the number of bytes written" do
      source = "def f\n  $stderr.write(\"done\")\nend\n"

      expect(covered?(source, "\"done\"", Prism::StringNode)).to be false
      expect(covered?(source, "$stderr.write(\"done\")", Prism::CallNode)).to be false
    end

    it "covers a stream write whose value is dropped" do
      expect(covered?("def f\n  $stderr.write(\"done\")\n  1\nend\n", "\"done\"", Prism::StringNode)).to be true
    end
  end

  it "leaves output whose argument may change state" do
    expect(covered?("puts(queue.pop!)\n", "queue.pop!", Prism::CallNode)).to be false
    expect(covered?("puts(queue.pop)\n", "puts(queue.pop)", Prism::CallNode)).to be false
  end
end
