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

    # test-unit gems live under test/ with a _test.rb suffix
    # just like minitest; without this the resolver defaults to spec/_spec.rb and
    # every test-unit mutation resolves to nothing (:unresolved).
    it "passes test/_test.rb kwargs for :test_unit" do
      expect(Evilution::SpecResolver).to receive(:new).with(
        test_dir: "test", test_suffix: "_test.rb", request_dir: "integration"
      )
      described_class.call(integration: :test_unit)
    end
  end
end
