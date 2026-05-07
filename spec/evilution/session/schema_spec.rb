# frozen_string_literal: true

require "evilution/session/schema"

RSpec.describe Evilution::Session::Schema do
  describe "CURRENT_VERSION" do
    it "is 1" do
      expect(described_class::CURRENT_VERSION).to eq(1)
    end
  end

  describe ".validate!" do
    it "does not raise when data has no schema_version (treated as current)" do
      expect { described_class.validate!({}) }.not_to raise_error
    end

    it "does not raise when schema_version is the current version" do
      expect { described_class.validate!({ "schema_version" => 1 }) }.not_to raise_error
    end

    it "accepts symbol keys" do
      expect { described_class.validate!({ schema_version: 1 }) }.not_to raise_error
    end

    it "reads schema_version from symbol-keyed data when validating" do
      expect { described_class.validate!({ schema_version: 99 }) }
        .to raise_error(Evilution::Error, /schema_version 99/)
    end

    it "raises Evilution::Error when schema_version is newer than supported" do
      expect { described_class.validate!({ "schema_version" => 99 }) }
        .to raise_error(Evilution::Error, /schema_version 99.*newer than this evilution gem/)
    end

    it "raises Evilution::Error when schema_version is 0" do
      expect { described_class.validate!({ "schema_version" => 0 }) }
        .to raise_error(Evilution::Error, /invalid schema_version 0.*positive Integer/)
    end

    it "raises Evilution::Error when schema_version is negative" do
      expect { described_class.validate!({ "schema_version" => -1 }) }
        .to raise_error(Evilution::Error, /invalid schema_version -1.*positive Integer/)
    end

    it "raises Evilution::Error when schema_version is not an integer" do
      expect { described_class.validate!({ "schema_version" => "one" }) }
        .to raise_error(Evilution::Error, /invalid schema_version "one".*positive Integer/)
    end

    it "includes the source path in the future-version error message" do
      expect { described_class.validate!({ "schema_version" => 99 }, source: ".evilution/results/foo.json") }
        .to raise_error(Evilution::Error, %r{ at \.evilution/results/foo\.json})
    end

    it "includes the source path in the invalid-value error message" do
      expect { described_class.validate!({ "schema_version" => -1 }, source: ".evilution/results/bad.json") }
        .to raise_error(Evilution::Error, %r{ at \.evilution/results/bad\.json})
    end

    it "omits the source clause when no source is given for an invalid value" do
      expect { described_class.validate!({ "schema_version" => -1 }) }
        .to raise_error(Evilution::Error, /\Ainvalid schema_version -1: must be/)
    end

    it "omits the source clause when no source is given for a future version" do
      expect { described_class.validate!({ "schema_version" => 99 }) }
        .to raise_error(Evilution::Error, /\Asession file has schema_version 99/)
    end

    it "tells the user to upgrade the gem on a future schema_version" do
      expect { described_class.validate!({ "schema_version" => 99 }) }
        .to raise_error(Evilution::Error, /Upgrade the evilution gem/)
    end

    it "includes the current supported schema_version in the future-version error" do
      expect { described_class.validate!({ "schema_version" => 99 }) }
        .to raise_error(Evilution::Error, /current: #{described_class::CURRENT_VERSION}/)
    end

    it "raises when schema_version equals CURRENT_VERSION + 1 (boundary)" do
      future = described_class::CURRENT_VERSION + 1
      expect { described_class.validate!({ "schema_version" => future }) }
        .to raise_error(Evilution::Error, /schema_version #{future}/)
    end
  end
end
