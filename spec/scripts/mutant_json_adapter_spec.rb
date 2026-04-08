# frozen_string_literal: true

load File.expand_path("../../scripts/mutant_json_adapter", __dir__)

RSpec.describe MutantJsonAdapter do
  describe MutantJsonAdapter::OutputParser do
    let(:parser) { described_class.new }
    let(:subject_stub) do
      MutantJsonAdapter::MethodExtractor::MethodInfo.new("Foo#bar", 10, "")
    end

    it "parses a single mutation diff" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; true; end
        +def foo
        +  false
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.size).to eq(1)
      expect(results.first["file"]).to eq("foo.rb")
      expect(results.first["line"]).to eq(10)
      expect(results.first["subject"]).to eq("Foo#bar")
      expect(results.first["diff"]).to include("-def foo; true; end")
    end

    it "parses multiple mutation diffs" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; true; end
        +def foo
        +  raise
        +end
        @@ -1 +1,3 @@
        -def foo; true; end
        +def foo
        +  false
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.size).to eq(2)
    end

    it "returns empty array for empty output" do
      results = parser.parse("", subject: subject_stub, file_path: "foo.rb")

      expect(results).to be_empty
    end

    it "classifies raise insertion" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; true; end
        +def foo
        +  raise
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.first["operator"]).to eq("raise_insertion")
    end

    it "classifies super replacement" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; true; end
        +def foo
        +  super
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.first["operator"]).to eq("super_replacement")
    end

    it "classifies nil replacement" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; x > 0; end
        +def foo
        +  nil
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.first["operator"]).to eq("nil_replacement")
    end

    it "classifies boolean swap" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; true; end
        +def foo
        +  false
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.first["operator"]).to eq("boolean_swap")
    end

    it "classifies literal boundary mutations" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; x > 0; end
        +def foo
        +  x > 1
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.first["operator"]).to eq("literal_boundary")
    end

    it "classifies equality change" do
      raw = <<~OUTPUT
        @@ -1 +1,3 @@
        -def foo; x > 0; end
        +def foo
        +  x.eql?(0)
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.first["operator"]).to eq("equality_change")
    end

    it "classifies removal when body is empty" do
      raw = <<~OUTPUT
        @@ -1 +1,2 @@
        -def foo; x > 0; end
        +def foo
        +end
      OUTPUT

      results = parser.parse(raw, subject: subject_stub, file_path: "foo.rb")

      expect(results.first["operator"]).to eq("removal")
    end
  end

  describe MutantJsonAdapter::MethodExtractor do
    it "extracts methods from a Ruby file" do
      fixture = File.expand_path("../support/fixtures/simple_class.rb", __dir__)
      skip "fixture not found" unless File.exist?(fixture)

      subjects = described_class.new(fixture).extract

      expect(subjects).not_to be_empty
      expect(subjects.first).to respond_to(:name, :line_number, :source)
    end

    it "correctly extracts from files with multi-byte characters" do
      fixture = File.expand_path("../support/fixtures/multibyte_class.rb", __dir__)
      skip "fixture not found" unless File.exist?(fixture)

      subjects = described_class.new(fixture).extract

      subjects.each do |s|
        expect(s.source).to start_with("def ")
        expect(s.source.strip).to end_with("end")
      end
    end
  end
end
