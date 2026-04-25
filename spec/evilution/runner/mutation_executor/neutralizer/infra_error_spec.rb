# frozen_string_literal: true

require "evilution/mutation"
require "evilution/result/mutation_result"
require "evilution/runner/mutation_executor/neutralizer/infra_error"

RSpec.describe Evilution::Runner::MutationExecutor::Neutralizer::InfraError do
  let(:neutralizer) { described_class.new }
  let(:mutation) { instance_double(Evilution::Mutation, file_path: "lib/foo.rb") }

  def result(status:, error_class: nil, error_message: nil, error_backtrace: nil)
    Evilution::Result::MutationResult.new(
      mutation: mutation, status: status, duration: 0.01,
      error_class: error_class, error_message: error_message, error_backtrace: error_backtrace
    )
  end

  it "returns the result unchanged when there is no error" do
    r = result(status: :killed)
    expect(neutralizer.call(r)).to be(r)
  end

  it "returns the result unchanged when error_class is not infra" do
    r = result(status: :error, error_class: "RuntimeError", error_backtrace: ["spec/spec_helper.rb:1"])
    expect(neutralizer.call(r)).to be(r)
  end

  it "returns the result unchanged when error origin is not infra (first frame is mutation code)" do
    r = result(status: :error, error_class: "NameError", error_backtrace: ["lib/foo.rb:5", "spec/spec_helper.rb:1"])
    expect(neutralizer.call(r)).to be(r)
  end

  it "neutralizes :error when error_class is infra and first frame matches infra path" do
    r = result(status: :error, error_class: "LoadError", error_backtrace: ["spec/spec_helper.rb:1"])
    out = neutralizer.call(r)
    expect(out.status).to eq(:neutral)
    expect(out.error_class).to eq("LoadError")
  end

  it "neutralizes :error when first frame matches rails_helper path" do
    r = result(status: :error, error_class: "NameError", error_backtrace: ["spec/rails_helper.rb:3"])
    expect(neutralizer.call(r).status).to eq(:neutral)
  end

  it "neutralizes :error when first frame matches spec/support/" do
    r = result(status: :error, error_class: "LoadError", error_backtrace: ["spec/support/init.rb:1"])
    expect(neutralizer.call(r).status).to eq(:neutral)
  end

  it "neutralizes :killed when error_class is in INFRA_CRASH_CLASSES (no backtrace check)" do
    r = result(status: :killed, error_class: "Timeout::Error")
    expect(neutralizer.call(r).status).to eq(:neutral)
  end

  it "neutralizes :killed for ActiveRecord timeout/lock crashes" do
    %w[ActiveRecord::StatementTimeout ActiveRecord::Deadlocked ActiveRecord::ConnectionTimeoutError
       ActiveRecord::LockWaitTimeout SQLite3::BusyException].each do |klass|
      r = result(status: :killed, error_class: klass)
      expect(neutralizer.call(r).status).to eq(:neutral), "expected #{klass} → :neutral"
    end
  end

  it "does not neutralize :killed when error_class is NOT in crash list" do
    r = result(status: :killed, error_class: "RuntimeError")
    expect(neutralizer.call(r)).to be(r)
  end
end
