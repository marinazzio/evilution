# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::IndexToFetch do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/index_access.rb", __dir__) }
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  describe "#call" do
    it "replaces hash[:key] with hash.fetch(:key)" do
      muts = mutations_for("hash_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.fetch(:key)")
    end

    it "replaces array[0] with array.fetch(0)" do
      muts = mutations_for("array_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a.fetch(0)")
    end

    it "replaces hash[\"name\"] with hash.fetch(\"name\")" do
      muts = mutations_for("string_key_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include('h.fetch("name")')
    end

    it "replaces hash[k] with hash.fetch(k)" do
      muts = mutations_for("variable_key_access")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.fetch(k)")
    end

    it "does not mutate multi-argument [] access" do
      muts = mutations_for("multi_arg_access")

      expect(muts).to be_empty
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("hash_access")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("index_to_fetch")
      end
    end

    it "does not mutate methods without [] access" do
      muts = mutations_for("no_index_access")

      expect(muts).to be_empty
    end

    def mutations_from_source(method_name, src)
      tmpfile = Tempfile.new(["index_to_fetch", ".rb"])
      tmpfile.write(src)
      tmpfile.close
      subject = Evilution::AST::Parser.new.call(tmpfile.path)
                                      .find { |s| s.name.end_with?("##{method_name}") }
      described_class.new.call(subject)
    ensure
      tmpfile.unlink if tmpfile
    end

    it "does not mutate a non-[] one-argument method call (name guard)" do
      muts = mutations_from_source(
        "dig_call", "class C\n  def dig_call(h)\n    h.dig(:k)\n  end\nend\n"
      )

      expect(muts).to be_empty
    end

    it "does not mutate an empty [] call with no arguments" do
      muts = mutations_from_source(
        "empty_index", "class C\n  def empty_index(h)\n    h[]\n  end\nend\n"
      )

      expect(muts).to be_empty
    end

    it "mutates a [] access nested inside another [] access" do
      muts = mutations_from_source(
        "nested_index", "class C\n  def nested_index(h, a)\n    h[a[0]]\n  end\nend\n"
      )

      expect(muts.length).to eq(2)
      expect(muts.map(&:mutated_source)).to include(
        a_string_matching(/h\.fetch\(a\[0\]\)/),
        a_string_matching(/h\[a\.fetch\(0\)\]/)
      )
    end

    it "generates valid replacement when multi-byte characters precede the target" do
      multibyte_source = <<~RUBY
        class Lookup
          # ค้นหาข้อมูลจากแฮช
          def find(h)
            h[:key]
          end
        end
      RUBY

      tmpfile = Tempfile.new(["multibyte_fetch", ".rb"])
      tmpfile.write(multibyte_source)
      tmpfile.close

      src = File.read(tmpfile.path)
      tree = Prism.parse(src).value
      finder = Evilution::AST::SubjectFinder.new(src, tmpfile.path)
      finder.visit(tree)
      subject = finder.subjects.find { |s| s.name.end_with?("#find") }

      muts = described_class.new.call(subject)

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("h.fetch(:key)")
      expect(muts.first.mutated_source).to be_valid_encoding
    ensure
      tmpfile&.unlink
    end
  end
end
