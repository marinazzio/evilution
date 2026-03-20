# frozen_string_literal: true

RSpec.describe Evilution::Result::MutationResult do
  let(:mutation) { double("Mutation") }

  describe "status predicates" do
    it "identifies killed mutations" do
      result = described_class.new(mutation: mutation, status: :killed)

      expect(result).to be_killed
      expect(result).not_to be_survived
    end

    it "identifies survived mutations" do
      result = described_class.new(mutation: mutation, status: :survived)

      expect(result).to be_survived
      expect(result).not_to be_killed
    end

    it "identifies timed out mutations" do
      result = described_class.new(mutation: mutation, status: :timeout)

      expect(result).to be_timeout
    end

    it "identifies error mutations" do
      result = described_class.new(mutation: mutation, status: :error)

      expect(result).to be_error
    end

    it "identifies neutral mutations" do
      result = described_class.new(mutation: mutation, status: :neutral)

      expect(result).to be_neutral
      expect(result).not_to be_survived
      expect(result).not_to be_killed
    end

    it "identifies equivalent mutations" do
      result = described_class.new(mutation: mutation, status: :equivalent)

      expect(result).to be_equivalent
      expect(result).not_to be_survived
      expect(result).not_to be_killed
    end
  end

  it "rejects invalid statuses" do
    expect { described_class.new(mutation: mutation, status: :invalid) }
      .to raise_error(ArgumentError, /invalid status/)
  end

  it "stores duration" do
    result = described_class.new(mutation: mutation, status: :killed, duration: 1.5)

    expect(result.duration).to eq(1.5)
  end

  it "stores killing test" do
    result = described_class.new(mutation: mutation, status: :killed, killing_test: "spec/user_spec.rb:12")

    expect(result.killing_test).to eq("spec/user_spec.rb:12")
  end

  it "defaults duration to 0.0" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result.duration).to eq(0.0)
  end

  it "stores test_command" do
    result = described_class.new(mutation: mutation, status: :killed, test_command: "rspec --format progress spec")

    expect(result.test_command).to eq("rspec --format progress spec")
  end

  it "defaults test_command to nil" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result.test_command).to be_nil
  end

  it "is frozen" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result).to be_frozen
  end
end
