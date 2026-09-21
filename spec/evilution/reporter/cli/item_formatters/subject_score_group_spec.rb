# frozen_string_literal: true

RSpec.describe Evilution::Reporter::CLI::ItemFormatters::SubjectScoreGroup do
  subject(:formatter) { described_class.new }

  def score(name, killed:, verified:, total: nil, survived: 0, file: "app/helpers/example_helper.rb")
    Evilution::Result::SubjectScore.new(
      name: name, file_path: file, total: total || verified, killed: killed,
      verified: verified, survived: survived
    )
  end

  describe "#format" do
    it "puts the file above its subjects" do
      group = [
        score("Helper#summary_for", killed: 0, verified: 0, total: 18),
        score("Helper#label_for", killed: 9, verified: 12, survived: 3)
      ]

      expect(formatter.format(group)).to eq(
        "  app/helpers/example_helper.rb\n    " \
        "#summary_for  0.00%  (0/18)  nothing reached this subject\n    " \
        "#label_for  75.00%  (9/12)"
      )
    end

    it "formats a group of one" do
      group = [score("Helper#label_for", killed: 1, verified: 2, survived: 1)]

      expect(formatter.format(group)).to eq(
        "  app/helpers/example_helper.rb\n    #label_for  50.00%  (1/2)"
      )
    end
  end
end
