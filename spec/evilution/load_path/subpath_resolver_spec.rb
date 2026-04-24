# frozen_string_literal: true

require "tmpdir"
require "evilution/load_path/subpath_resolver"

RSpec.describe Evilution::LoadPath::SubpathResolver do
  subject(:resolver) { described_class.new }

  describe "#call" do
    it "returns the shortest relative path under any LOAD_PATH entry" do
      Dir.mktmpdir("evilution_lp_short") do |root|
        sub = File.join(root, "lib")
        FileUtils.mkdir_p(sub)
        target = File.join(sub, "foo/bar.rb")
        FileUtils.mkdir_p(File.dirname(target))
        File.write(target, "")

        $LOAD_PATH.unshift(root, sub)
        begin
          expect(resolver.call(target)).to eq("foo/bar.rb")
        ensure
          $LOAD_PATH.delete(root)
          $LOAD_PATH.delete(sub)
        end
      end
    end

    it "returns nil when the path lies outside every LOAD_PATH entry" do
      Dir.mktmpdir("evilution_lp_miss") do |dir|
        target = File.join(dir, "outside.rb")
        File.write(target, "")

        expect(resolver.call(target)).to be_nil
      end
    end

    it "handles LOAD_PATH entries that already end with a slash" do
      Dir.mktmpdir("evilution_lp_slash") do |root|
        target = File.join(root, "x.rb")
        File.write(target, "")
        trailing = "#{root}/"

        $LOAD_PATH.unshift(trailing)
        begin
          expect(resolver.call(target)).to eq("x.rb")
        ensure
          $LOAD_PATH.delete(trailing)
        end
      end
    end

    it "expands the given file path before checking" do
      Dir.mktmpdir("evilution_lp_rel") do |root|
        target = File.join(root, "rel.rb")
        File.write(target, "")

        $LOAD_PATH.unshift(root)
        begin
          Dir.chdir(root) do
            expect(resolver.call("rel.rb")).to eq("rel.rb")
          end
        ensure
          $LOAD_PATH.delete(root)
        end
      end
    end
  end
end
