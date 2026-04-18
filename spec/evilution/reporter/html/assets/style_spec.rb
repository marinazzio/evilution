# frozen_string_literal: true

require "evilution/result/mutation_result"

RSpec.describe "HTML reporter stylesheet" do
  let(:css) do
    File.read(File.expand_path("../../../../../lib/evilution/reporter/html/assets/style.css", __dir__))
  end

  Evilution::Result::MutationResult::STATUSES.each do |status|
    it "defines .map-line.#{status}" do
      expect(css).to match(/\.map-line\.#{status}\b/)
    end

    it "defines .status-badge.#{status}" do
      expect(css).to match(/\.status-badge\.#{status}\b/)
    end
  end
end
