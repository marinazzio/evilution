# frozen_string_literal: true

require "tmpdir"

RSpec.describe Evilution::Cache::SpecDigest do
  around do |example|
    Dir.mktmpdir("evilution_spec_digest") { |dir| Dir.chdir(dir) { example.run } }
  end

  before do
    FileUtils.mkdir_p("spec/models")
    File.write("spec/a_spec.rb", "a")
    File.write("spec/models/b_spec.rb", "b")
  end

  it "is nil when there are no files" do
    expect(described_class.new.call([])).to be_nil
    expect(described_class.new.call(nil)).to be_nil
  end

  it "takes a pathname like its path" do
    expect(described_class.new.call([Pathname.new("spec/a_spec.rb")])).to eq(described_class.new.call(["spec/a_spec.rb"]))
  end

  it "tells apart two files of the same content" do
    File.write("spec/c_spec.rb", "a")

    expect(described_class.new.call(["spec/c_spec.rb"])).not_to eq(described_class.new.call(["spec/a_spec.rb"]))
  end

  it "tells apart two files read by the same instance" do
    digest = described_class.new

    expect(digest.call(["spec/a_spec.rb"])).not_to eq(digest.call(["spec/models/b_spec.rb"]))
  end

  it "covers the Ruby files in the subdirectories of a directory" do
    FileUtils.mkdir_p("spec/models/deep")
    File.write("spec/models/deep/d_spec.rb", "d")
    before = described_class.new.call(["spec/models"])
    File.write("spec/models/deep/d_spec.rb", "d2")

    expect(described_class.new.call(["spec/models"])).not_to eq(before)
  end

  it "covers only the files under the directory" do
    before = described_class.new.call(["spec/models"])
    File.write("spec/a_spec.rb", "a2")
    File.write("spec/models/notes.txt", "n")

    expect(described_class.new.call(["spec/models"])).to eq(before)
  end

  it "is the same for the same files in any order" do
    expect(described_class.new.call(["spec/a_spec.rb", "spec/models/b_spec.rb"]))
      .to eq(described_class.new.call(["spec/models/b_spec.rb", "spec/a_spec.rb", "spec/a_spec.rb"]))
  end

  it "changes when a file's content changes" do
    before = described_class.new.call(["spec/a_spec.rb"])
    File.write("spec/a_spec.rb", "a2")

    expect(described_class.new.call(["spec/a_spec.rb"])).not_to eq(before)
  end

  it "changes when a different file is named" do
    expect(described_class.new.call(["spec/a_spec.rb"])).not_to eq(described_class.new.call(["spec/models/b_spec.rb"]))
  end

  it "covers the Ruby files under a directory" do
    before = described_class.new.call(["spec/models"])
    File.write("spec/models/b_spec.rb", "b2")

    expect(described_class.new.call(["spec/models"])).not_to eq(before)
  end

  it "notices a file appearing under a directory" do
    before = described_class.new.call(["spec/models"])
    File.write("spec/models/c_spec.rb", "c")

    expect(described_class.new.call(["spec/models"])).not_to eq(before)
  end

  it "tells a missing file apart from an empty one" do
    missing = described_class.new.call(["spec/c_spec.rb"])
    File.write("spec/c_spec.rb", "")

    expect(described_class.new.call(["spec/c_spec.rb"])).not_to eq(missing)
  end

  it "reads each file once per instance" do
    digest = described_class.new
    allow(File).to receive(:binread).and_call_original

    digest.call(["spec/a_spec.rb"])
    digest.call(["spec/a_spec.rb", "spec/models/b_spec.rb"])

    expect(File).to have_received(:binread).with("spec/a_spec.rb").once
  end
end
