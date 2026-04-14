# frozen_string_literal: true

require "stringio"
require "evilution/cli/command"
require "evilution/cli/parsed_args"
require "evilution/cli/result"

RSpec.describe Evilution::CLI::Command do
  let(:parsed) { Evilution::CLI::ParsedArgs.new(command: :dummy, options: { foo: 1 }) }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  let(:happy_subclass) do
    Class.new(described_class) do
      def perform
        0
      end
    end
  end

  let(:error_subclass) do
    Class.new(described_class) do
      def perform
        raise Evilution::Error, "kaboom"
      end
    end
  end

  it "wraps a successful perform in a Result" do
    result = happy_subclass.new(parsed, stdout: stdout, stderr: stderr).call
    expect(result.exit_code).to eq(0)
    expect(result.error).to be_nil
  end

  it "catches Evilution::Error and returns exit code 2 carrying the error" do
    result = error_subclass.new(parsed, stdout: stdout, stderr: stderr).call
    expect(result.exit_code).to eq(2)
    expect(result.error).to be_a(Evilution::Error)
    expect(result.error.message).to eq("kaboom")
  end

  it "raises NotImplementedError when perform is not overridden" do
    expect { described_class.new(parsed).call }.to raise_error(NotImplementedError)
  end
end
