# frozen_string_literal: true

RSpec.describe "evilution.gemspec" do
  let(:spec) { Gem::Specification.load(File.expand_path("../../evilution.gemspec", __dir__)) }

  it "constrains prism to a version that ships IfNode#subsequent (>= 1.5, < 2)" do
    expect(spec).not_to be_nil, "evilution.gemspec must load successfully"

    prism_dep = spec.dependencies.find { |d| d.name == "prism" }

    expect(prism_dep).not_to be_nil, "evilution.gemspec must declare prism as a runtime dependency"
    expect(prism_dep.type).to eq(:runtime)
    expect(prism_dep.requirement.satisfied_by?(Gem::Version.new("0.19.0"))).to be(false)
    expect(prism_dep.requirement.satisfied_by?(Gem::Version.new("1.0.0"))).to be(false)
    expect(prism_dep.requirement.satisfied_by?(Gem::Version.new("1.5.0"))).to be(true)
    expect(prism_dep.requirement.satisfied_by?(Gem::Version.new("1.9.9"))).to be(true)
    expect(prism_dep.requirement.satisfied_by?(Gem::Version.new("2.0.0"))).to be(false)
  end
end
