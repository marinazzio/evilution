# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/local_declaration"

RSpec.describe Evilution::AST::LocalDeclaration do
  subject(:declaration) { described_class.new }

  # Ruby decides while parsing which names are local variables, so an
  # assignment that never runs still makes a later `factor` read the local
  # rather than call a method.
  {
    "an assignment" => "    factor = 3\n",
    "an assignment inside a conditional" => "if x > 1000\n  factor = 3\nend\n",
    "an operator assignment" => "total += 1\n",
    "an or-assignment" => "memo ||= {}\n",
    "an and-assignment" => "flag &&= ready\n",
    "a multiple assignment" => "a, b = pair\n",
    "a rescued exception" => "begin\n  run\nrescue => e\n  e\nend\n",
    "a regexp's named capture" => "/(?<word>\\w+)/ =~ text\n",
    "a pattern's capture" => "case value\nin [first, *]\n  first\nend\n",
    "a for loop's variable" => "for item in items\n  item\nend\n"
  }.each do |what, source|
    it "finds #{what}" do
      expect(declaration.in?(source)).to be(true)
    end
  end

  {
    "an instance variable assignment" => "@factor = 3\n",
    "a method call" => "compute(factor)\n",
    "a comparison" => "factor == 3\n",
    "a constant" => "LIMIT = 3\n"
  }.each do |what, source|
    it "finds none in #{what}" do
      expect(declaration.in?(source)).to be(false)
    end
  end

  # Lines cut out of a method need not parse on their own.
  it "finds one in lines that do not parse on their own" do
    expect(declaration.in?("if x > 1000\n  factor = 3\n")).to be(true)
  end

  it "assumes one when there is no source to look at" do
    expect(declaration.in?(nil)).to be(true)
  end
end
