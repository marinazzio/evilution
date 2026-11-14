# frozen_string_literal: true

require "spec_helper"
require "evilution/ast/skip_sites/logging"
require_relative "../../../support/skip_site_helpers"

RSpec.describe Evilution::AST::SkipSites::Logging do
  include SkipSiteHelpers

  it "is named logging" do
    expect(described_class.new.name).to eq(:logging)
  end

  %w[logger.info @logger.debug @@logger.warn $logger.error LOGGER.fatal Rails.logger.unknown self.logger.add
     config.logger.log App::LOGGER.info].each do |call|
    it "covers the message of #{call}" do
      expect(covered?("#{call}(\"saved\")\n", "\"saved\"", Prism::StringNode)).to be true
    end
  end

  it "covers the call itself, so deleting it is skipped" do
    expect(covered?("def f\n  logger.info(\"saved\")\n  1\nend\n", "logger.info(\"saved\")", Prism::CallNode)).to be true
  end

  it "covers a message built in a block" do
    expect(covered?("logger.debug { \"saved \#{id}\" }\n", "id", Prism::CallNode)).to be true
  end

  it "leaves a level method sent to something other than a logger" do
    expect(covered?("record.info(\"saved\")\n", "\"saved\"", Prism::StringNode)).to be false
  end

  it "leaves a logger method that is not a level" do
    expect(covered?("logger.level = compute(:debug)\n", ":debug", Prism::SymbolNode)).to be false
  end

  it "leaves a predicate asked of the logger" do
    expect(covered?("return unless logger.debug?\n", "logger.debug?", Prism::CallNode)).to be false
  end

  it "leaves the condition guarding the log line" do
    expect(covered?("logger.info(\"x\") if verbose?\n", "verbose?", Prism::CallNode)).to be false
  end

  context "with a deprecation warning" do
    %w[ActiveSupport::Deprecation.warn ActiveSupport.deprecator.warn Rails.deprecator.warn
       deprecator.warn @deprecator.warn deprecator.deprecation_warning].each do |call|
      it "covers the message of #{call}" do
        expect(covered?("#{call}(\"old\")\n", "\"old\"", Prism::StringNode)).to be true
      end
    end

    it "covers Kernel#warn in the deprecated category" do
      expect(covered?("warn(\"old\", category: :deprecated)\n", "\"old\"", Prism::StringNode)).to be true
    end

    it "leaves Kernel#warn in another category" do
      expect(covered?("warn(\"old\", category: :experimental)\n", "\"old\"", Prism::StringNode)).to be false
    end

    it "leaves Kernel#warn without a category" do
      expect(covered?("warn(\"old\")\n", "\"old\"", Prism::StringNode)).to be false
    end

    it "leaves a bare warn" do
      expect(covered?("warn\n", "warn", Prism::CallNode)).to be false
    end

    it "covers the deprecated category among other keywords" do
      source = "warn(\"old\", uplevel: 1, category: :deprecated)\n"

      expect(covered?(source, "\"old\"", Prism::StringNode)).to be true
    end

    it "leaves another keyword that is :deprecated, a category given as a string, and splatted keywords" do
      expect(covered?("warn(\"old\", kind: :deprecated)\n", "\"old\"", Prism::StringNode)).to be false
      expect(covered?("warn(\"old\", category: \"deprecated\")\n", "\"old\"", Prism::StringNode)).to be false
      expect(covered?("warn(\"old\", **opts)\n", "\"old\"", Prism::StringNode)).to be false
    end

    it "leaves warn in the deprecated category sent to another receiver" do
      expect(covered?("io.warn(\"old\", category: :deprecated)\n", "\"old\"", Prism::StringNode)).to be false
    end

    it "leaves a deprecator's other methods" do
      expect(covered?("deprecator.behavior(\"old\")\n", "\"old\"", Prism::StringNode)).to be false
    end
  end

  context "when the message calls a method that may change state" do
    let(:source) { "logger.info(\"left: \#{queue.pop!}\")\n" }

    it "leaves the call" do
      expect(covered?(source, "queue.pop!", Prism::CallNode)).to be false
    end

    it "leaves the log line as a whole, so deleting it is not skipped" do
      expect(covered?(source, source.chomp, Prism::CallNode)).to be false
    end

    it "still covers the literal text" do
      expect(covered?(source, "left: ", Prism::StringNode)).to be true
    end
  end

  it "covers a read-only argument next to one that may change state" do
    source = "logger.add(level, \"x\", sink.flush!)\n"

    expect(covered?(source, "level", Prism::CallNode)).to be true
    expect(covered?(source, "sink.flush!", Prism::CallNode)).to be false
  end

  it "leaves a level method sent to no receiver" do
    expect(covered?("info(\"saved\")\n", "\"saved\"", Prism::StringNode)).to be false
  end

  it "leaves the log line as a whole when one argument may change state and another only reads" do
    source = "logger.add(level, sink.flush!)\n"

    expect(covered?(source, source.chomp, Prism::CallNode)).to be false
  end

  it "leaves the log line as a whole when an argument may change state, whatever its block" do
    source = "logger.info(queue.pop!) { \"x\" }\n"

    expect(covered?(source, source.chomp, Prism::CallNode)).to be false
  end

  it "leaves a log line that passes a block argument" do
    expect(covered?("logger.info(&formatter)\n", "logger.info(&formatter)", Prism::CallNode)).to be false
  end
end
