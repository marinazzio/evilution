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

  it "descends into classes nested inside another class" do
    source = <<~RUBY
      class Outer
        class Inner < Base
        end
      end
    RUBY
    inheritance = scan(source)

    expect(inheritance["Outer::Inner"]).to eq("Outer::Base")
  end

  it "pops module context so a later sibling module is not polluted" do
    source = <<~RUBY
      module First
        class A; end
      end

      module Second
        class B; end
      end
    RUBY
    inheritance = scan(source)

    expect(inheritance).to include("First::A" => nil, "Second::B" => nil)
  end

  it "pops class context after leaving a nested class" do
    source = <<~RUBY
      class Wrapper
        class Inside; end
      end

      class Sibling < Base; end
    RUBY
    inheritance = scan(source)

    expect(inheritance["Sibling"]).to eq("Base")
  end

  describe "#constant_name fallbacks" do
    it "uses a String name when the node responds to #name but not #full_name" do
      fake_node = Struct.new(:name).new(:Widget)
      scanner = described_class.new

      result = scanner.send(:constant_name, fake_node)

      expect(result).to eq("Widget")
      expect(result).to be_a(String)
    end

    it "falls back to #slice when the node responds to neither #full_name nor #name" do
      fake_node = Object.new
      def fake_node.slice = "Sliced"
      scanner = described_class.new

      expect(scanner.send(:constant_name, fake_node)).to eq("Sliced")
    end
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
