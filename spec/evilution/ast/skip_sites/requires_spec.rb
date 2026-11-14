# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_sites/requires"
require_relative "../../../support/skip_site_helpers"

RSpec.describe Evilution::AST::SkipSites::Requires do
  include SkipSiteHelpers

  it "is named requires" do
    expect(described_class.new.name).to eq(:requires)
  end

  it "covers a require at the top of the file" do
    expect(covered?("require \"json\"\n", "\"json\"", Prism::StringNode)).to be true
  end

  it "covers the call itself, so deleting it is skipped" do
    expect(covered?("require \"json\"\n", "require \"json\"", Prism::CallNode)).to be true
  end

  it "covers require_relative in a class body" do
    source = "class A\n  require_relative \"a/b\"\n  def f; end\nend\n"

    expect(covered?(source, "\"a/b\"", Prism::StringNode)).to be true
  end

  it "covers Kernel.require" do
    expect(covered?("Kernel.require \"json\"\n", "\"json\"", Prism::StringNode)).to be true
  end

  it "covers a path built from __dir__" do
    expect(covered?("require File.join(__dir__, \"b\")\n", "\"b\"", Prism::StringNode)).to be true
  end

  it "covers a block inside the require's own arguments, which runs while the file loads" do
    source = "require File.join(parts.map { |part| part })\n"

    expect(covered?(source, "part", Prism::LocalVariableReadNode)).to be true
  end

  it "leaves a require inside a method, which loads lazily" do
    expect(covered?("def f\n  require \"json\"\nend\n", "\"json\"", Prism::StringNode)).to be false
  end

  it "leaves a require inside a block, which runs later" do
    expect(covered?("included do\n  require \"json\"\nend\n", "\"json\"", Prism::StringNode)).to be false
  end

  it "leaves a require inside a lambda" do
    expect(covered?("LOAD = -> { require \"json\" }\n", "\"json\"", Prism::StringNode)).to be false
  end

  it "leaves the condition guarding a require" do
    source = "require \"oj\" if defined?(RUBY_ENGINE)\n"

    expect(covered?(source, "defined?(RUBY_ENGINE)", Prism::DefinedNode)).to be false
  end

  it "leaves a require sent to another receiver" do
    expect(covered?("loader.require \"json\"\n", "\"json\"", Prism::StringNode)).to be false
  end
end
