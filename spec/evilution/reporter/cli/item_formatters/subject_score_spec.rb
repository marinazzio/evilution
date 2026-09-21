# frozen_string_literal: true

RSpec.describe Evilution::Reporter::CLI::ItemFormatters::SubjectScore do
  subject(:formatter) { described_class.new }

  def score(name:, total:, killed:, verified:, survived: 0, file: "app/helpers/example_helper.rb")
    Evilution::Result::SubjectScore.new(
      name: name, file_path: file, total: total, killed: killed, verified: verified, survived: survived
    )
  end

  describe "#format" do
    it "reports a partly-killed subject with its score and counts" do
      row = score(name: "Helper#label_for", total: 12, killed: 9, verified: 12, survived: 3)

      expect(formatter.format(row)).to eq("    #label_for  75.00%  (9/12)")
    end

    # The file's own score says nothing about a method no example reaches, which
    # is the case this report exists for.
    it "says so when nothing reached the subject" do
      row = score(name: "Helper#summary_for", total: 18, killed: 0, verified: 0)

      expect(formatter.format(row)).to eq("    #summary_for  0.00%  (0/18)  nothing reached this subject")
    end

    # Subjects are grouped under their file, so the class prefix would repeat
    # the heading; the method is what distinguishes the rows.
    it "keeps a singleton method's receiver" do
      row = score(name: "Helper.build", total: 4, killed: 2, verified: 4, survived: 2)

      expect(formatter.format(row)).to eq("    .build  50.00%  (2/4)")
    end

    it "keeps a name that carries no class prefix" do
      row = score(name: "#orphan", total: 2, killed: 1, verified: 2, survived: 1)

      expect(formatter.format(row)).to eq("    #orphan  50.00%  (1/2)")
    end
  end
end
