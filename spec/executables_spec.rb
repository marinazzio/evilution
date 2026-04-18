# frozen_string_literal: true

RSpec.describe "executables" do
  let(:exe_dir) { File.expand_path("../exe", __dir__) }
  let(:evilution_path) { File.join(exe_dir, "evilution") }
  let(:evil_path) { File.join(exe_dir, "evil") }

  it "ships an 'evilution' executable" do
    expect(File.executable?(evilution_path)).to be true
  end

  it "ships an 'evil' alternative executable" do
    expect(File.executable?(evil_path)).to be true
  end

  it "evil has identical contents to evilution" do
    aggregate_failures do
      expect(File.exist?(evil_path)).to be true
      expect(File.exist?(evilution_path)).to be true
      expect(File.binread(evil_path)).to eq(File.binread(evilution_path))
    end
  end
end
