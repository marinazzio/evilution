# frozen_string_literal: true

require "tmpdir"
require "evilution/integration/loading/test_load_path"

RSpec.describe Evilution::Integration::Loading::TestLoadPath do
  around do |example|
    saved = $LOAD_PATH.dup
    example.run
    $LOAD_PATH.replace(saved)
  end

  def make_tree(base)
    FileUtils.mkdir_p(File.join(base, "test", "unit", "transition"))
    FileUtils.mkdir_p(File.join(base, "spec", "lib"))
    FileUtils.touch(File.join(base, "test", "test_helper.rb"))
    FileUtils.touch(File.join(base, "test", "unit", "transition", "transition_test.rb"))
    FileUtils.touch(File.join(base, "spec", "lib", "thing_spec.rb"))
  end

  describe ".dirs_for" do
    it "includes the conventional test/ and spec/ roots under base when they exist" do
      Dir.mktmpdir do |base|
        make_tree(base)
        dirs = described_class.dirs_for(["test/unit/transition/transition_test.rb"], base)
        expect(dirs).to include(File.join(base, "test"))
      end
    end

    it "includes the resolved file's own directory" do
      Dir.mktmpdir do |base|
        make_tree(base)
        dirs = described_class.dirs_for(["test/unit/transition/transition_test.rb"], base)
        expect(dirs).to include(File.join(base, "test", "unit", "transition"))
      end
    end

    it "includes the topmost test/spec ancestor of a nested file (so test/unit -> test)" do
      Dir.mktmpdir do |base|
        make_tree(base)
        dirs = described_class.dirs_for(["test/unit/transition/transition_test.rb"], base)
        # test root present, but not the intermediate test/unit as a "root"
        expect(dirs).to include(File.join(base, "test"))
      end
    end

    it "handles spec/-rooted layouts (spec/lib -> spec)" do
      Dir.mktmpdir do |base|
        make_tree(base)
        dirs = described_class.dirs_for(["spec/lib/thing_spec.rb"], base)
        expect(dirs).to include(File.join(base, "spec"), File.join(base, "spec", "lib"))
      end
    end

    it "omits directories that do not exist" do
      Dir.mktmpdir do |base|
        # no tree created
        dirs = described_class.dirs_for(["test/unit/x_test.rb"], base)
        expect(dirs).to be_empty
      end
    end

    it "returns each directory only once" do
      Dir.mktmpdir do |base|
        make_tree(base)
        files = ["test/unit/transition/transition_test.rb", "test/test_helper.rb"]
        dirs = described_class.dirs_for(files, base)
        expect(dirs).to eq(dirs.uniq)
      end
    end
  end

  describe ".add!" do
    it "prepends the computed dirs to $LOAD_PATH" do
      Dir.mktmpdir do |base|
        make_tree(base)
        described_class.add!(["test/unit/transition/transition_test.rb"], base: base)
        expect($LOAD_PATH).to include(File.join(base, "test"))
      end
    end

    it "does not duplicate a directory already on $LOAD_PATH" do
      Dir.mktmpdir do |base|
        make_tree(base)
        test_root = File.join(base, "test")
        $LOAD_PATH.unshift(test_root)
        described_class.add!(["test/unit/transition/transition_test.rb"], base: base)
        expect($LOAD_PATH.count(test_root)).to eq(1)
      end
    end

    it "makes a bare require of a helper at the test root resolve" do
      Dir.mktmpdir do |base|
        FileUtils.mkdir_p(File.join(base, "test", "unit"))
        helper = File.join(base, "test", "test_helper.rb")
        File.write(helper, "TEST_LOAD_PATH_SPEC_HELPER_LOADED = true\n")
        File.write(File.join(base, "test", "unit", "x_test.rb"), "")

        described_class.add!(["test/unit/x_test.rb"], base: base)

        expect { require "test_helper" }.not_to raise_error
        expect(defined?(TEST_LOAD_PATH_SPEC_HELPER_LOADED)).to eq("constant")
      ensure
        $LOADED_FEATURES.delete(helper)
        Object.send(:remove_const, :TEST_LOAD_PATH_SPEC_HELPER_LOADED) if defined?(TEST_LOAD_PATH_SPEC_HELPER_LOADED)
      end
    end
  end
end
