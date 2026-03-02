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
      lines = subjects.map { |s| [s.name, s.line_number] }.to_h

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
end
