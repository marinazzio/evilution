# frozen_string_literal: true

require "evilution/compare/normalizer"

RSpec.describe Evilution::Compare::Normalizer do
  subject(:normalizer) { described_class.new }

  describe "#from_evilution" do
    let(:json) do
      {
        "version" => "0.22.0",
        "summary" => { "total" => 2 },
        "killed" => [
          {
            "operator" => "Arithmetic::Swap",
            "file" => "lib/foo.rb",
            "line" => 42,
            "status" => "killed",
            "duration" => 0.01,
            "diff" => "- a + b\n+ a - b"
          }
        ],
        "survived" => [
          {
            "operator" => "BooleanLiteral::Flip",
            "file" => "lib/bar.rb",
            "line" => 7,
            "status" => "survived",
            "duration" => 0.02,
            "diff" => "- true\n+ false"
          }
        ]
      }
    end

    it "returns one Record per mutation across all buckets" do
      records = normalizer.from_evilution(json)
      expect(records.size).to eq(2)
    end

    it "populates source as :evilution" do
      records = normalizer.from_evilution(json)
      expect(records.map(&:source)).to all(eq(:evilution))
    end

    it "populates file_path, line, status, operator, and diff_body" do
      records = normalizer.from_evilution(json)
      killed = records.find { |r| r.status == :killed }
      expect(killed).to have_attributes(
        file_path: "lib/foo.rb",
        line: 42,
        status: :killed,
        operator: "Arithmetic::Swap",
        diff_body: "- a + b\n+ a - b"
      )
    end

    it "computes a fingerprint for each record" do
      records = normalizer.from_evilution(json)
      records.each { |r| expect(r.fingerprint).to match(/\A[0-9a-f]{64}\z/) }
    end

    it "retains the raw hash for downstream reporting" do
      records = normalizer.from_evilution(json)
      killed = records.find { |r| r.status == :killed }
      expect(killed.raw).to include("operator" => "Arithmetic::Swap", "file" => "lib/foo.rb")
    end

    def mut(status, line)
      {
        "operator" => "Op",
        "file" => "lib/x.rb",
        "line" => line,
        "status" => status,
        "duration" => 0.0,
        "diff" => "- a\n+ b"
      }
    end

    it "maps every bucket to the correct canonical status" do
      json = {
        "killed" => [mut("killed", 1)],
        "survived" => [mut("survived", 2)],
        "timed_out" => [mut("timeout", 3)],
        "errors" => [mut("error", 4)],
        "neutral" => [mut("neutral", 5)],
        "equivalent" => [mut("equivalent", 6)],
        "unresolved" => [mut("unresolved", 7)],
        "unparseable" => [mut("unparseable", 8)]
      }
      records = normalizer.from_evilution(json)
      expect(records.map(&:status))
        .to eq(%i[killed survived timeout error neutral equivalent unresolved unparseable])
    end

    it "raises InvalidInput when 'file' is missing, carrying the record index" do
      json = { "killed" => [{ "line" => 1, "status" => "killed", "diff" => "" }] }
      expect { normalizer.from_evilution(json) }
        .to raise_error(Evilution::Compare::InvalidInput) { |e|
          expect(e.message).to include("file")
          expect(e.index).to eq(0)
        }
    end

    it "raises InvalidInput when 'line' is missing" do
      json = { "killed" => [{ "file" => "lib/x.rb", "status" => "killed", "diff" => "" }] }
      expect { normalizer.from_evilution(json) }
        .to raise_error(Evilution::Compare::InvalidInput, /line/)
    end

    it "raises InvalidInput on unknown status" do
      json = { "killed" => [{ "file" => "lib/x.rb", "line" => 1, "status" => "mystery", "diff" => "" }] }
      expect { normalizer.from_evilution(json) }
        .to raise_error(Evilution::Compare::InvalidInput, /mystery/)
    end

    it "ignores unknown top-level keys" do
      json = { "killed" => [], "mystery_key" => "ignored" }
      expect { normalizer.from_evilution(json) }.not_to raise_error
    end
  end

  describe "#from_mutant" do
    let(:json) do
      {
        "subject_results" => [
          {
            "source_path" => "lib/foo.rb",
            "coverage_results" => [
              {
                "mutation_result" => {
                  "mutation_identification" => "evil:Foo#bar:lib/foo.rb:42:a1b2c",
                  "mutation_type" => "evil",
                  "mutation_diff" => "--- Foo#bar\n+++ Foo#bar:evil:a1b2c\n@@ -1,1 +1,1 @@\n-  a + b\n+  a - b"
                },
                "criteria_result" => { "process_abort" => false, "test_result" => true, "timeout" => false }
              }
            ]
          }
        ]
      }
    end

    it "returns one Record per mutation_result" do
      expect(normalizer.from_mutant(json).size).to eq(1)
    end

    it "hoists source_path from subject onto each record" do
      expect(normalizer.from_mutant(json).first.file_path).to eq("lib/foo.rb")
    end

    it "parses the line number from mutation_identification" do
      expect(normalizer.from_mutant(json).first.line).to eq(42)
    end

    it "populates source as :mutant and operator as nil" do
      record = normalizer.from_mutant(json).first
      expect(record.source).to eq(:mutant)
      expect(record.operator).to be_nil
    end

    it "computes a fingerprint matching an equivalent evilution record" do
      mutant_record = normalizer.from_mutant(json).first

      evilution_json = {
        "killed" => [{
          "operator" => "Arithmetic::Swap",
          "file" => "lib/foo.rb",
          "line" => 42,
          "status" => "killed",
          "duration" => 0.0,
          "diff" => "-   a + b\n+   a - b"
        }]
      }
      evilution_record = normalizer.from_evilution(evilution_json).first

      expect(mutant_record.fingerprint).to eq(evilution_record.fingerprint)
    end

    def subject_with(mutation_type:, test_result:, process_abort:, timeout:)
      {
        "subject_results" => [{
          "source_path" => "lib/x.rb",
          "coverage_results" => [{
            "mutation_result" => {
              "mutation_identification" => "evil:X#y:lib/x.rb:1:abcde",
              "mutation_type" => mutation_type,
              "mutation_diff" => "--- x\n+++ x\n@@ -1 +1 @@\n-a\n+b"
            },
            "criteria_result" => {
              "test_result" => test_result,
              "process_abort" => process_abort,
              "timeout" => timeout
            }
          }]
        }]
      }
    end

    it "maps neutral mutation_type to :neutral regardless of criteria" do
      json = subject_with(mutation_type: "neutral", test_result: true, process_abort: true, timeout: true)
      expect(normalizer.from_mutant(json).first.status).to eq(:neutral)
    end

    it "maps noop mutation_type to :neutral" do
      json = subject_with(mutation_type: "noop", test_result: false, process_abort: false, timeout: false)
      expect(normalizer.from_mutant(json).first.status).to eq(:neutral)
    end

    it "prefers :timeout over :error over :killed when multiple criteria are true" do
      json = subject_with(mutation_type: "evil", test_result: true, process_abort: true, timeout: true)
      expect(normalizer.from_mutant(json).first.status).to eq(:timeout)
    end

    it "maps process_abort alone to :error" do
      json = subject_with(mutation_type: "evil", test_result: false, process_abort: true, timeout: false)
      expect(normalizer.from_mutant(json).first.status).to eq(:error)
    end

    it "maps test_result alone to :killed" do
      json = subject_with(mutation_type: "evil", test_result: true, process_abort: false, timeout: false)
      expect(normalizer.from_mutant(json).first.status).to eq(:killed)
    end

    it "maps all-false evil mutation to :survived" do
      json = subject_with(mutation_type: "evil", test_result: false, process_abort: false, timeout: false)
      expect(normalizer.from_mutant(json).first.status).to eq(:survived)
    end

    it "raises InvalidInput on unknown shape" do
      json = subject_with(mutation_type: "???", test_result: false, process_abort: false, timeout: false)
      expect { normalizer.from_mutant(json) }.to raise_error(Evilution::Compare::InvalidInput)
    end

    it "raises InvalidInput when subject is missing source_path" do
      json = { "subject_results" => [{ "coverage_results" => [] }] }
      expect { normalizer.from_mutant(json) }
        .to raise_error(Evilution::Compare::InvalidInput, /source_path/)
    end

    it "raises InvalidInput when mutation_identification is unparseable" do
      json = {
        "subject_results" => [{
          "source_path" => "lib/x.rb",
          "coverage_results" => [{
            "mutation_result" => { "mutation_identification" => "garbage", "mutation_type" => "evil", "mutation_diff" => "" },
            "criteria_result" => { "test_result" => false, "process_abort" => false, "timeout" => false }
          }]
        }]
      }
      expect { normalizer.from_mutant(json) }
        .to raise_error(Evilution::Compare::InvalidInput, /parse line/)
    end

    it "raises InvalidInput when mutation line is non-integer" do
      json = {
        "subject_results" => [{
          "source_path" => "lib/x.rb",
          "coverage_results" => [{
            "mutation_result" => {
              "mutation_identification" => "evil:X#y:lib/x.rb:NaN:abcde",
              "mutation_type" => "evil",
              "mutation_diff" => ""
            },
            "criteria_result" => { "test_result" => false, "process_abort" => false, "timeout" => false }
          }]
        }]
      }
      expect { normalizer.from_mutant(json) }
        .to raise_error(Evilution::Compare::InvalidInput, /non-integer/)
    end

    it "parses the line even when the subject path contains a colon (Windows drive)" do
      json = {
        "subject_results" => [{
          "source_path" => "C:/src/x.rb",
          "coverage_results" => [{
            "mutation_result" => {
              "mutation_identification" => "evil:X#y:C:/src/x.rb:77:abcde",
              "mutation_type" => "evil",
              "mutation_diff" => "--- x\n+++ x\n@@ -1 +1 @@\n-a\n+b"
            },
            "criteria_result" => { "test_result" => true, "process_abort" => false, "timeout" => false }
          }]
        }]
      }
      expect(normalizer.from_mutant(json).first.line).to eq(77)
    end
  end

  describe "fixture end-to-end" do
    let(:fixture_dir) { File.expand_path("../../support/fixtures/compare", __dir__) }

    it "produces 4 records from each fixture with matching fingerprints" do
      require "json"
      evo = normalizer.from_evilution(JSON.parse(File.read("#{fixture_dir}/evilution.json")))
      mut = normalizer.from_mutant(JSON.parse(File.read("#{fixture_dir}/mutant.json")))

      expect(evo.size).to eq(4)
      expect(mut.size).to eq(4)

      evo_fps = evo.map(&:fingerprint).sort
      mut_fps = mut.map(&:fingerprint).sort
      expect(evo_fps).to eq(mut_fps)
    end

    it "preserves distinct canonical statuses across both tools" do
      require "json"
      evo = normalizer.from_evilution(JSON.parse(File.read("#{fixture_dir}/evilution.json")))
      mut = normalizer.from_mutant(JSON.parse(File.read("#{fixture_dir}/mutant.json")))

      expect(evo.map(&:status).sort).to eq(%i[killed killed survived timeout])
      expect(mut.map(&:status).sort).to eq(%i[killed killed survived timeout])
    end
  end
end
