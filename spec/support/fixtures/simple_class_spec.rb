# frozen_string_literal: true

require_relative "simple_class"

RSpec.describe User do
  subject(:user) { described_class.new("Alice", 25) }

  describe "#adult?" do
    it "returns true for age >= 18" do
      expect(user.adult?).to be true
    end

    it "returns false for age < 18" do
      expect(described_class.new("Bob", 10).adult?).to be false
    end
  end

  describe "#greeting" do
    it "includes the name" do
      expect(user.greeting).to eq("Hello, Alice")
    end
  end
end

RSpec.describe Admin do
  describe "#admin?" do
    it "returns true" do
      expect(described_class.new.admin?).to be true
    end
  end
end
