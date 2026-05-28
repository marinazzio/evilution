# frozen_string_literal: true

RSpec.describe Evilution do
  it "has a version number" do
    expect(Evilution::VERSION).not_to be nil
  end

  it "defines the Error class" do
    expect(Evilution::Error).to be < StandardError
  end

  describe ".project_base_dir" do
    around do |example|
      previous = Evilution.instance_variable_get(:@in_isolated_worker)
      example.run
    ensure
      Evilution.instance_variable_set(:@in_isolated_worker, previous)
    end

    it "returns Dir.pwd when the isolated-worker flag is unset" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(Evilution.project_base_dir).to eq(dir)
        end
      end
    end

    it "returns Evilution::PROJECT_ROOT when the isolated-worker flag is set" do
      Evilution.in_isolated_worker!

      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(Evilution.project_base_dir).to eq(Evilution::PROJECT_ROOT)
        end
      end
    end
  end
end
