# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_sites/error_messages"
require_relative "../../../support/skip_site_helpers"

RSpec.describe Evilution::AST::SkipSites::ErrorMessages do
  include SkipSiteHelpers

  it "is named error_messages" do
    expect(described_class.new.name).to eq(:error_messages)
  end

  context "with a class and a message" do
    let(:source) { "def f(x)\n  raise ArgumentError, \"bad value\" if x.nil?\nend\n" }

    it "covers the message" do
      expect(covered?(source, "\"bad value\"", Prism::StringNode)).to be true
    end

    it "leaves the raised class" do
      expect(covered?(source, "ArgumentError", Prism::ConstantReadNode)).to be false
    end

    it "leaves the condition guarding the raise" do
      expect(covered?(source, "x.nil?", Prism::CallNode)).to be false
    end

    it "leaves the raise itself" do
      expect(covered?(source, "raise ArgumentError, \"bad value\"", Prism::CallNode)).to be false
    end
  end

  it "covers a message given alone" do
    expect(covered?("raise \"boom\"\n", "\"boom\"", Prism::StringNode)).to be true
  end

  it "covers the message of fail" do
    expect(covered?("fail Error, \"boom\"\n", "\"boom\"", Prism::StringNode)).to be true
  end

  it "covers the message of Kernel.raise" do
    expect(covered?("Kernel.raise Error, \"boom\"\n", "\"boom\"", Prism::StringNode)).to be true
  end

  it "leaves a raise sent to another receiver" do
    expect(covered?("task.raise Error, \"boom\"\n", "\"boom\"", Prism::StringNode)).to be false
  end

  it "leaves a local variable named like a constructor" do
    expect(covered?("new = Error\nraise new\n", "new", Prism::LocalVariableReadNode, nth: 0)).to be false
  end

  it "leaves a value given alone that is not a string" do
    expect(covered?("raise error_for(code)\n", "code", Prism::CallNode)).to be false
  end

  it "leaves the cause keyword" do
    source = "raise Error, \"boom\", cause: original\n"

    expect(covered?(source, "original", Prism::CallNode)).to be false
  end

  it "leaves the cause keyword of a raise given only a class" do
    expect(covered?("raise Error, cause: original\n", "original", Prism::CallNode)).to be false
  end

  it "covers a message given alone with a cause" do
    expect(covered?("raise \"boom\", cause: original\n", "\"boom\"", Prism::StringNode)).to be true
  end

  it "leaves the backtrace argument" do
    expect(covered?("raise Error, \"boom\", trace\n", "trace", Prism::CallNode)).to be false
  end

  it "leaves the arguments of a raise with a splat" do
    expect(covered?("raise *args, \"boom\"\n", "\"boom\"", Prism::StringNode)).to be false
  end

  context "with an exception built in place" do
    it "covers its string arguments" do
      expect(covered?("raise Error.new(\"boom\")\n", "\"boom\"", Prism::StringNode)).to be true
    end

    it "covers the string arguments of .exception on a constant path" do
      expect(covered?("raise Errors::Bad.exception(\"boom\")\n", "\"boom\"", Prism::StringNode)).to be true
    end

    it "leaves its other arguments, which the exception may keep as data" do
      expect(covered?("raise Error.new(record)\n", "record", Prism::CallNode)).to be false
    end

    it "leaves the arguments of an error built with a splat" do
      expect(covered?("raise Error.new(*args, \"boom\")\n", "\"boom\"", Prism::StringNode)).to be false
    end

    it "leaves the arguments of another class method" do
      expect(covered?("raise Error.build(\"boom\")\n", "\"boom\"", Prism::StringNode)).to be false
    end

    it "leaves the exception class" do
      expect(covered?("raise Error.new(\"boom\")\n", "Error", Prism::ConstantReadNode)).to be false
    end

    it "leaves an exception built on a receiver that is not a constant" do
      expect(covered?("raise klass.new(\"boom\")\n", "\"boom\"", Prism::StringNode)).to be false
    end
  end

  context "with an interpolated message" do
    it "covers reads of variables and attributes" do
      source = "raise Error, \"bad \#{name}: \#{@record.id} (\#{opts[:key].inspect})\"\n"

      expect(covered?(source, "@record.id", Prism::CallNode)).to be true
      expect(covered?(source, ":key", Prism::SymbolNode)).to be true
      expect(covered?(source, "bad ", Prism::StringNode)).to be true
    end

    it "covers the whole message when it reads only" do
      source = "raise Error, \"bad \#{name}\"\n"

      expect(covered?(source, "\"bad \#{name}\"", Prism::InterpolatedStringNode)).to be true
    end

    context "when the message calls a method that may change state" do
      let(:source) { "raise Error, \"left: \#{queue.pop!} of \#{count(items)}\"\n" }

      it "leaves the call" do
        expect(covered?(source, "queue.pop!", Prism::CallNode)).to be false
      end

      it "leaves a call that takes arguments" do
        expect(covered?(source, "items", Prism::CallNode)).to be false
      end

      it "leaves the message as a whole" do
        expect(covered?(source, source[13..-2], Prism::InterpolatedStringNode)).to be false
      end

      it "still covers its literal text" do
        expect(covered?(source, "left: ", Prism::StringNode)).to be true
        expect(covered?(source, " of ", Prism::StringNode)).to be true
      end
    end

    it "leaves a string passed to a call that may change state" do
      source = "raise Error, \"bad \#{lookup(\"key\")}\"\n"

      expect(covered?(source, "\"key\"", Prism::StringNode)).to be false
    end

    it "leaves a block in the message" do
      source = "raise Error, \"bad \#{names.map { |n| n }}\"\n"

      expect(covered?(source, "n", Prism::LocalVariableReadNode)).to be false
    end

    it "leaves an assignment in the message" do
      source = "raise Error, \"bad \#{@last = name}\"\n"

      expect(covered?(source, "name", Prism::CallNode)).to be false
    end
  end

  it "covers a message built by format from reads" do
    source = "raise Error, format(\"bad %s\", name)\n"

    expect(covered?(source, "\"bad %s\"", Prism::StringNode)).to be true
    expect(covered?(source, "name", Prism::CallNode)).to be true
  end

  it "leaves a string inside a message that is not itself a string and may change state" do
    expect(covered?("raise Error, [\"a\", queue.pop!]\n", "\"a\"", Prism::StringNode)).to be false
  end

  it "leaves a message built by a method of the code under test" do
    source = "raise Error, describe_failure(record)\n"

    expect(covered?(source, "record", Prism::CallNode)).to be false
  end
end
