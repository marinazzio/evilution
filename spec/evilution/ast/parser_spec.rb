# frozen_string_literal: true

RSpec.describe Evilution::AST::Parser do
  subject(:parser) { described_class.new }

  let(:fixture_path) { File.expand_path("../../support/fixtures/simple_class.rb", __dir__) }

  describe "#call" do
    it "returns an array of Subject objects" do
      subjects = parser.call(fixture_path)

      expect(subjects).to all(be_a(Evilution::Subject))
    end

    it "extracts all method definitions" do
      subjects = parser.call(fixture_path)
      names = subjects.map(&:name)

      expect(names).to contain_exactly(
        "User#initialize",
        "User#adult?",
        "User#greeting",
        "Admin#admin?"
      )
    end

    it "sets correct file path on each subject" do
      subjects = parser.call(fixture_path)

      subjects.each do |subject|
        expect(subject.file_path).to eq(fixture_path)
      end
    end

    it "sets correct line numbers" do
      subjects = parser.call(fixture_path)
      lines = subjects.to_h { |s| [s.name, s.line_number] }

      expect(lines["User#initialize"]).to eq(4)
      expect(lines["User#adult?"]).to eq(9)
      expect(lines["User#greeting"]).to eq(13)
      expect(lines["Admin#admin?"]).to eq(19)
    end

    it "captures method source code" do
      subjects = parser.call(fixture_path)
      adult_subject = subjects.find { |s| s.name == "User#adult?" }

      expect(adult_subject.source).to include("def adult?")
      expect(adult_subject.source).to include("@age >= 18")
    end

    it "stores the Prism DefNode" do
      subjects = parser.call(fixture_path)

      subjects.each do |subject|
        expect(subject.node).to be_a(Prism::DefNode)
      end
    end
  end

  context "with nested modules" do
    let(:nested_source) do
      <<~RUBY
        module Foo
          class Bar
            def baz
              42
            end
          end
        end
      RUBY
    end

    it "builds fully-qualified names" do
      tmpfile = Tempfile.new(["nested", ".rb"])
      tmpfile.write(nested_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("Foo::Bar#baz")
    ensure
      tmpfile&.unlink
    end
  end

  context "with compact class notation" do
    let(:compact_source) do
      <<~RUBY
        class Foo::Bar
          def baz
            42
          end
        end
      RUBY
    end

    it "handles Foo::Bar style class names" do
      tmpfile = Tempfile.new(["compact", ".rb"])
      tmpfile.write(compact_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("Foo::Bar#baz")
    ensure
      tmpfile&.unlink
    end
  end

  context "with class methods (def self.foo)" do
    let(:class_method_source) do
      <<~RUBY
        class Service
          def self.call(input)
            new(input).run
          end

          def run
            :ok
          end
        end
      RUBY
    end

    it "names class methods with dot separator" do
      tmpfile = Tempfile.new(["class_method", ".rb"])
      tmpfile.write(class_method_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      names = subjects.map(&:name)

      expect(names).to contain_exactly("Service.call", "Service#run")
    ensure
      tmpfile&.unlink
    end

    it "captures class method source" do
      tmpfile = Tempfile.new(["class_method", ".rb"])
      tmpfile.write(class_method_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      call_subject = subjects.find { |s| s.name == "Service.call" }

      expect(call_subject.source).to include("def self.call")
    ensure
      tmpfile&.unlink
    end
  end

  context "with namespaced class methods" do
    let(:namespaced_class_method_source) do
      <<~RUBY
        module Api
          class Client
            def self.connect(url)
              new(url)
            end
          end
        end
      RUBY
    end

    it "builds fully-qualified names for class methods" do
      tmpfile = Tempfile.new(["ns_class_method", ".rb"])
      tmpfile.write(namespaced_class_method_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("Api::Client.connect")
    ensure
      tmpfile&.unlink
    end
  end

  context "with top-level methods" do
    let(:toplevel_source) do
      <<~RUBY
        def standalone
          "hello"
        end
      RUBY
    end

    it "uses just method name with hash prefix" do
      tmpfile = Tempfile.new(["toplevel", ".rb"])
      tmpfile.write(toplevel_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("#standalone")
    ensure
      tmpfile&.unlink
    end
  end

  context "with multi-byte characters" do
    let(:multibyte_source) do
      # Cyrillic comment before the method to shift byte vs char offsets
      <<~RUBY
        class Greeter
          # Приветствие пользователя
          def greet(name)
            "Hello, \#{name}!"
          end
        end
      RUBY
    end

    it "extracts correct method source when file contains multi-byte characters" do
      tmpfile = Tempfile.new(["multibyte", ".rb"])
      tmpfile.write(multibyte_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      greet = subjects.find { |s| s.name == "Greeter#greet" }

      expect(greet).not_to be_nil
      expect(greet.source).to start_with("def greet(name)")
      expect(greet.source).to include("Hello")
      expect(greet.source).to end_with("end")
    ensure
      tmpfile&.unlink
    end

    it "preserves correct encoding in extracted source" do
      tmpfile = Tempfile.new(["multibyte", ".rb"])
      tmpfile.write(multibyte_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      greet = subjects.find { |s| s.name == "Greeter#greet" }

      expect(greet.source.encoding).to eq(Encoding::UTF_8)
      expect(greet.source).to be_valid_encoding
    ensure
      tmpfile&.unlink
    end

    it "extracts correct method source with Thai comments (3-byte UTF-8)" do
      thai_source = <<~RUBY
        class Calculator
          # คำนวณผลรวมของตัวเลข
          def sum(a, b)
            a + b
          end

          # ตรวจสอบว่าเป็นจำนวนคู่หรือไม่
          def even?(n)
            n.even?
          end
        end
      RUBY

      tmpfile = Tempfile.new(["thai", ".rb"])
      tmpfile.write(thai_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      sum_subject = subjects.find { |s| s.name == "Calculator#sum" }
      even_subject = subjects.find { |s| s.name == "Calculator#even?" }

      expect(sum_subject.source).to start_with("def sum(a, b)")
      expect(sum_subject.source).to include("a + b")
      expect(even_subject.source).to start_with("def even?(n)")
      expect(even_subject.source).to include("n.even?")
    ensure
      tmpfile&.unlink
    end
  end
end
