# frozen_string_literal: true

RSpec.describe Evilution::AST::InheritanceScanner do
  def scan(source)
    result = Prism.parse(source)
    scanner = described_class.new
    scanner.visit(result.value)
    scanner.inheritance
  end

  it "detects class with explicit superclass" do
    inheritance = scan("class Child < Base; end")

    expect(inheritance).to eq("Child" => "Base")
  end

  it "detects class without superclass" do
    inheritance = scan("class Standalone; end")

    expect(inheritance).to eq("Standalone" => nil)
  end

  it "detects namespaced classes" do
    source = <<~RUBY
      module Foo
        class Bar < Baz
        end
      end
    RUBY
    inheritance = scan(source)

    expect(inheritance).to eq("Foo::Bar" => "Foo::Baz")
  end

  it "detects multiple classes in one file" do
    source = <<~RUBY
      class Base; end
      class ChildA < Base; end
      class ChildB < Base; end
    RUBY
    inheritance = scan(source)

    expect(inheritance).to eq("Base" => nil, "ChildA" => "Base", "ChildB" => "Base")
  end

  it "scans multiple files via .call" do
    allow(File).to receive(:read).with("a.rb").and_return("class A; end")
    allow(File).to receive(:read).with("b.rb").and_return("class B < A; end")

    inheritance = described_class.call(["a.rb", "b.rb"])

    expect(inheritance).to eq("A" => nil, "B" => "A")
  end

  it "qualifies unqualified superclass within module context" do
    source = <<~RUBY
      module Models
        class Base; end
        class User < Base; end
      end
    RUBY
    inheritance = scan(source)

    expect(inheritance["Models::User"]).to eq("Models::Base")
  end

  it "preserves already-qualified superclass names" do
    source = <<~RUBY
      module App
        class Service < ::Base::Handler; end
      end
    RUBY
    inheritance = scan(source)

    expect(inheritance["App::Service"]).to eq("::Base::Handler")
  end

  it "skips unreadable files" do
    allow(File).to receive(:read).with("good.rb").and_return("class Good; end")
    allow(File).to receive(:read).with("missing.rb").and_raise(Errno::ENOENT)

    inheritance = described_class.call(["good.rb", "missing.rb"])

    expect(inheritance).to eq("Good" => nil)
  end

  it "skips files that fail to parse" do
    allow(File).to receive(:read).with("good.rb").and_return("class Good; end")
    allow(File).to receive(:read).with("bad.rb").and_return("class {{{")

    inheritance = described_class.call(["good.rb", "bad.rb"])

    expect(inheritance).to eq("Good" => nil)
  end
end
