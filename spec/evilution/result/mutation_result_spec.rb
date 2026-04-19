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

    it "identifies unresolved mutations" do
      result = described_class.new(mutation: mutation, status: :unresolved)

      expect(result).to be_unresolved
      expect(result).not_to be_survived
      expect(result).not_to be_killed
      expect(result).not_to be_error
    end

    it "identifies unparseable mutations" do
      result = described_class.new(mutation: mutation, status: :unparseable)

      expect(result).to be_unparseable
      expect(result).not_to be_error
      expect(result).not_to be_killed
      expect(result).not_to be_survived
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

  it "stores parent_rss_kb" do
    result = described_class.new(mutation: mutation, status: :killed, parent_rss_kb: 50_000)

    expect(result.parent_rss_kb).to eq(50_000)
  end

  it "defaults parent_rss_kb to nil" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result.parent_rss_kb).to be_nil
  end

  it "stores error_message" do
    result = described_class.new(mutation: mutation, status: :error, error_message: "boom")

    expect(result.error_message).to eq("boom")
  end

  it "defaults error_message to nil" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result.error_message).to be_nil
  end

  it "stores error_class" do
    result = described_class.new(mutation: mutation, status: :error, error_class: "SyntaxError")

    expect(result.error_class).to eq("SyntaxError")
  end

  it "defaults error_class to nil" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result.error_class).to be_nil
  end

  it "stores error_backtrace" do
    backtrace = ["lib/foo.rb:10:in `bar'", "lib/foo.rb:20:in `baz'"]
    result = described_class.new(mutation: mutation, status: :error, error_backtrace: backtrace)

    expect(result.error_backtrace).to eq(backtrace)
  end

  it "defaults error_backtrace to nil" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result.error_backtrace).to be_nil
  end

  it "freezes error_backtrace to prevent external mutation" do
    backtrace = ["lib/foo.rb:10:in `bar'"]
    result = described_class.new(mutation: mutation, status: :error, error_backtrace: backtrace)

    expect(result.error_backtrace).to be_frozen
    expect { result.error_backtrace << "extra" }.to raise_error(FrozenError)
  end

  it "does not reflect post-construction mutation of the caller's backtrace array" do
    backtrace = ["lib/foo.rb:10:in `bar'"]
    result = described_class.new(mutation: mutation, status: :error, error_backtrace: backtrace)

    backtrace << "lib/foo.rb:20:in `baz'"

    expect(result.error_backtrace).to eq(["lib/foo.rb:10:in `bar'"])
  end

  it "is frozen" do
    result = described_class.new(mutation: mutation, status: :killed)

    expect(result).to be_frozen
  end
end
