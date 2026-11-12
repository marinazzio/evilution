# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

# Runs evilution for real over one of its own files. The specs it runs then
# execute inside its worker, in the very process whose isolated-worker flag is
# up; a spec of the spec resolver that chdirs into a scratch project must still
# see that project, or it fails whatever the mutation and every mutant counts
# as killed.
RSpec.describe "Evilution mutating its own code", :aggregate_failures do
  root = File.expand_path("../../..", __dir__)
  fixture = File.expand_path("../../support/fixtures/self_mutation/sibling_spec_ranker_spec.rb.fixture", __dir__)
  target = "lib/evilution/spec_resolver/constant_references.rb"

  before(:context) do
    @report = Dir.mktmpdir("self_mutation") do |dir|
      # Kept under another name so this suite does not load it as its own.
      spec = File.join(dir, "sibling_spec_ranker_spec.rb")
      FileUtils.cp(fixture, spec)
      line = File.readlines(File.join(root, target)).index { |text| text.include?("RECEIVER_SEPARATORS =") } + 1
      command = [RbConfig.ruby, "-I", File.join(root, "lib"), File.join(root, "exe/evilution"), "run",
                 "#{target}:#{line}", "--spec", spec, "--format", "json"]
      out, err, status = Open3.capture3(*command, chdir: root)
      raise "evilution failed (#{status.exitstatus}): #{err}" if out.strip.empty?

      JSON.parse(out)
    end
  end

  let(:report) { @report }

  def entries(status)
    report.fetch(status, []).map { |entry| entry.fetch("diff").lines.last.strip }
  end

  it "reports no errors" do
    expect(report.dig("summary", "errors")).to eq(0)
  end

  it "reports a constant the spec does not pin as survived" do
    expect(entries("survived")).to include("+   RECEIVER_SEPARATORS = %i[DOT].freeze")
    expect(entries("killed")).not_to include("+   RECEIVER_SEPARATORS = %i[DOT].freeze")
  end

  it "still kills the mutants the spec catches" do
    expect(entries("killed")).to include("+   RECEIVER_SEPARATORS = %i[AMPERSAND_DOT].freeze",
                                         "+   RECEIVER_SEPARATORS = nil")
  end
end
