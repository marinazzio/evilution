# frozen_string_literal: true

require "spec_helper"
require "evilution/config/validators/since"

RSpec.describe Evilution::Config::Validators::Since do
  describe ".call" do
    it "returns nil for nil" do
      expect(described_class.call(nil, target: nil)).to be_nil
    end

    it "returns the ref as given" do
      expect(described_class.call("origin/main", target: nil)).to eq("origin/main")
    end

    it "strips the space around the ref" do
      expect(described_class.call(" main\n", target: nil)).to eq("main")
    end

    it "takes a symbol as its name" do
      expect(described_class.call(:main, target: nil)).to eq("main")
    end

    it "raises on an empty ref" do
      expect { described_class.call("", target: nil) }
        .to raise_error(Evilution::ConfigError, "--since needs a git ref, such as main or origin/main")
    end

    it "raises on a ref of spaces only" do
      expect { described_class.call("  ", target: nil) }
        .to raise_error(Evilution::ConfigError, "--since needs a git ref, such as main or origin/main")
    end

    it "raises when combined with a source glob target" do
      expect { described_class.call("main", target: "source:lib/**/*.rb") }
        .to raise_error(Evilution::ConfigError, /\A--since picks the changed files itself .*--target source:GLOB/)
    end

    it "accepts a method target" do
      expect(described_class.call("main", target: "Foo#bar")).to eq("main")
    end

    it "accepts a target that only mentions source: later on" do
      expect(described_class.call("main", target: "Foo::source:")).to eq("main")
    end

    it "leaves a source glob target alone without a ref" do
      expect(described_class.call(nil, target: "source:lib/**/*.rb")).to be_nil
    end
  end
end
