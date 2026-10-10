# frozen_string_literal: true

require "evilution/runner/subject_pipeline/target"

RSpec.describe Evilution::Runner::SubjectPipeline::Target do
  let(:subject_class) { Struct.new(:name) }

  def subject_named(name)
    subject_class.new(name)
  end

  def matched(text, *names)
    target = described_class.parse(text)
    names.select { |name| target.selects?(subject_named(name)) }
  end

  describe ".parse" do
    it "reads a source: prefix as a glob of files" do
      target = described_class.parse("source:lib/**/*.rb")

      expect([target.source_glob?, target.descendants?, target.method?]).to eq([true, false, false])
      expect(target.value).to eq("lib/**/*.rb")
    end

    it "reads a descendants: prefix as a class hierarchy" do
      target = described_class.parse("descendants:Billing::Base")

      expect([target.source_glob?, target.descendants?, target.method?]).to eq([false, true, false])
      expect(target.value).to eq("Billing::Base")
    end

    it "reads anything else as a method or class name" do
      target = described_class.parse("User#adult?")

      expect([target.source_glob?, target.descendants?, target.method?]).to eq([false, false, true])
      expect(target.value).to eq("User#adult?")
    end

    it "only takes a prefix from the start of the text" do
      expect(described_class.parse("Resource#source:").method?).to be(true)
      expect(described_class.parse("Resource#source:").value).to eq("Resource#source:")
    end

    it "keeps an empty glob or class name as written" do
      expect(described_class.parse("source:").source_glob?).to be(true)
      expect(described_class.parse("source:").value).to eq("")
    end

    it "returns NONE when no target was given" do
      expect(described_class.parse(nil)).to equal(described_class::NONE)
    end
  end

  describe "#to_s" do
    it "is the target as the user wrote it, prefix included" do
      expect(described_class.parse("descendants:Base").to_s).to eq("descendants:Base")
      expect("'#{described_class.parse("User#adult?")}'").to eq("'User#adult?'")
    end
  end

  describe "#selects?" do
    it "matches one method by its full name" do
      expect(matched("User#adult?", "User#adult?", "User#adult", "User.adult?", "Admin#adult?")).to eq(["User#adult?"])
      expect(matched("User.build", "User.build", "User#build")).to eq(["User.build"])
    end

    it "matches every method of a class named on its own" do
      expect(matched("User", "User#adult?", "User.build", "UserPolicy#call", "Admin::User#call", "User"))
        .to eq(["User#adult?", "User.build", "User"])
    end

    it "matches by name prefix when the target ends in # or ." do
      expect(matched("User#", "User#adult?", "User.build", "UserPolicy#call")).to eq(["User#adult?"])
      expect(matched("User.", "User#adult?", "User.build")).to eq(["User.build"])
    end

    it "matches classes by prefix when the target ends in *" do
      expect(matched("Billing::*", "Billing::Invoice#total", "Billing::Tax.rate", "Bill#total", "Other#billing"))
        .to eq(["Billing::Invoice#total", "Billing::Tax.rate"])
      expect(matched("User*", "User#adult?", "UserPolicy#call", "Admin#user")).to eq(["User#adult?", "UserPolicy#call"])
    end

    it "applies a * to the class name only" do
      expect(matched("User#a*", "User#adult?", "User#age")).to eq([])
    end

    it "leaves the value as written after matching" do
      target = described_class.parse("User*")
      target.selects?(subject_named("User#adult?"))

      expect(target.value).to eq("User*")
    end

    it "does not narrow by name when the target is a glob or a hierarchy" do
      expect(matched("source:lib/**/*.rb", "User#adult?", "Admin#call")).to eq(["User#adult?", "Admin#call"])
      expect(matched("descendants:Base", "User#adult?")).to eq(["User#adult?"])
    end
  end

  describe "NONE" do
    subject(:none) { described_class::NONE }

    it "is no kind of target" do
      expect([none.source_glob?, none.descendants?, none.method?]).to eq([false, false, false])
    end

    it "has no value and reads as an empty string" do
      expect(none.value).to be_nil
      expect(none.to_s).to eq("")
    end

    it "selects every subject" do
      expect(none.selects?(subject_named("User#adult?"))).to be(true)
    end
  end
end
