# frozen_string_literal: true

require "json"
require "spec_helper"

# Editors validate .evilution.yml against this schema, and it forbids keys it
# does not list: a key the config accepts but the schema leaves out is shown
# to the user as an error.
RSpec.describe "schema/evilution.config.schema.json" do
  schema_path = File.expand_path("../../../schema/evilution.config.schema.json", __dir__)

  it "lists every key a config file may set" do
    properties = JSON.parse(File.read(schema_path)).fetch("properties").keys

    expect(properties).to match_array(Evilution::Config::FileLoader::KNOWN_KEYS.map(&:to_s))
  end
end
