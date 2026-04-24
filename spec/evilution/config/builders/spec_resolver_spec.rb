# frozen_string_literal: true

require "spec_helper"
require "evilution/config/builders/spec_resolver"

RSpec.describe Evilution::Config::Builders::SpecResolver do
  describe ".call" do
    it "passes no kwargs for :rspec" do
      expect(Evilution::SpecResolver).to receive(:new).with(no_args)
      described_class.call(integration: :rspec)
    end

    it "passes minitest-shaped kwargs for :minitest" do
      expect(Evilution::SpecResolver).to receive(:new).with(
        test_dir: "test", test_suffix: "_test.rb", request_dir: "integration"
      )
      described_class.call(integration: :minitest)
    end
  end
end
