# frozen_string_literal: true

require "evilution/ast/parser"
require "evilution/mutator/operator/bang_method"

RSpec.describe Evilution::Mutator::Operator::BangMethod do
  let(:parser) { Evilution::AST::Parser.new }
  let(:fixture_path) { File.expand_path("../../../support/fixtures/bang_method.rb", __dir__) }
  let(:subjects) { parser.call(fixture_path) }

  let(:sort_bang_subject) { subjects.find { |s| s.name.include?("sort_bang") } }
  let(:sort_no_bang_subject) { subjects.find { |s| s.name.include?("sort_no_bang") } }
  let(:map_bang_subject) { subjects.find { |s| s.name.include?("map_bang") } }
  let(:uniq_bang_subject) { subjects.find { |s| s.name.include?("uniq_bang") } }
  let(:save_bang_subject) { subjects.find { |s| s.name.include?("save_bang") } }
  let(:no_bang_subject) { subjects.find { |s| s.name.include?("no_bang_method") } }
  let(:multiple_subject) { subjects.find { |s| s.name.include?("multiple_bangs") } }
  let(:strip_bang_subject) { subjects.find { |s| s.name.include?("strip_bang") } }

  describe "#call" do
    it "replaces bang method with non-bang equivalent" do
      mutations = described_class.new.call(sort_bang_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("- ", "items.sort!")
      expect(mutations.first.diff).to include("+ ", "items.sort")
      expect(mutations.first.diff).not_to match(/\+.*sort!/)
    end

    it "replaces non-bang method with bang equivalent" do
      mutations = described_class.new.call(sort_no_bang_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.mutated_source).to include("items.sort!")
    end

    it "replaces map! with map" do
      mutations = described_class.new.call(map_bang_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("- ", "items.map!")
      expect(mutations.first.diff).to include("+ ", "items.map")
      expect(mutations.first.diff).not_to match(/\+.*map!/)
    end

    it "replaces uniq! with uniq" do
      mutations = described_class.new.call(uniq_bang_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("- ", "items.uniq!")
      expect(mutations.first.diff).to include("+ ", "items.uniq")
      expect(mutations.first.diff).not_to match(/\+.*uniq!/)
    end

    it "replaces save! with save" do
      mutations = described_class.new.call(save_bang_subject)

      expect(mutations.length).to eq(1)
      expect(mutations.first.diff).to include("- ", "record.save!")
      expect(mutations.first.diff).to include("+ ", "record.save")
      expect(mutations.first.diff).not_to match(/\+.*save!/)
    end

    it "generates no mutations for methods without bang pairs" do
      mutations = described_class.new.call(no_bang_subject)

      expect(mutations).to be_empty
    end

    it "generates one mutation per bang method" do
      mutations = described_class.new.call(multiple_subject)

      expect(mutations.length).to eq(2)
    end

    it "produces valid Ruby for all mutations" do
      [sort_bang_subject, sort_no_bang_subject, map_bang_subject,
       uniq_bang_subject, save_bang_subject, strip_bang_subject].each do |subj|
        mutations = described_class.new.call(subj)
        mutations.each do |mutation|
          result = Prism.parse(mutation.mutated_source)
          expect(result.errors).to be_empty, "Invalid Ruby: #{mutation.mutated_source}"
        end
      end
    end

    it "sets correct operator_name" do
      mutations = described_class.new.call(sort_bang_subject)

      expect(mutations.first.operator_name).to eq("bang_method")
    end
  end
end
