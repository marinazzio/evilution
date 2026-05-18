# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/integration/loading/concern_state_cleaner"

RSpec.describe Evilution::Integration::Loading::ConcernStateCleaner do
  subject(:cleaner) { described_class.new }

  before(:all) do
    next if defined?(ActiveSupport::Concern)

    @as_module = Module.new
    stub_concern = Module.new do
      def self.extended(base)
        base.instance_variable_set(:@_not_a_concern, false)
      end
    end
    @as_module.const_set(:Concern, stub_concern)
    Object.const_set(:ActiveSupport, @as_module)
    @installed_as = true
  end

  after(:all) do
    next unless @installed_as

    Object.send(:remove_const, :ActiveSupport)
  end

  # Builds a proc whose `source_location` reports the given file path.
  def block_at(path)
    eval("proc {}", TOPLEVEL_BINDING, path, 1) # rubocop:disable Style/EvalWithLocation
  end

  describe "#initialize" do
    it "stores the default subpath resolver as a usable instance" do
      Dir.mktmpdir("evilution_concern_default") do |dir|
        target_path = File.join(dir, "concern.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        mod.instance_variable_set(:@_included_block, block_at(target_path))

        # A nil or wrong @subpath_resolver (method body replaced, or
        # SubpathResolver.new collapsed to the class) would raise here.
        expect { described_class.new.call(target_path) }.not_to raise_error
        expect(mod.instance_variable_defined?(:@_included_block)).to be false
      end
    end

    it "uses the injected subpath resolver" do
      injected = instance_double(Evilution::LoadPath::SubpathResolver)
      allow(injected).to receive(:call).and_return(nil)

      described_class.new(subpath_resolver: injected).call("/tmp/whatever.rb")

      expect(injected).to have_received(:call).with("/tmp/whatever.rb")
    end
  end

  describe "#call" do
    it "returns without error when ActiveSupport::Concern is undefined" do
      concern = ActiveSupport.send(:remove_const, :Concern)
      begin
        expect { cleaner.call("/tmp/absent.rb") }.not_to raise_error
      ensure
        ActiveSupport.const_set(:Concern, concern)
      end
    end

    it "does not touch concern state when ActiveSupport::Concern is undefined" do
      Dir.mktmpdir("evilution_concern_guard") do |dir|
        target_path = File.join(dir, "concern.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        mod.instance_variable_set(:@_included_block, block_at(target_path))

        concern = ActiveSupport.send(:remove_const, :Concern)
        begin
          cleaner.call(target_path)
        ensure
          ActiveSupport.const_set(:Concern, concern)
        end

        # With the guard removed the body would reference the now-undefined
        # ActiveSupport::Concern constant and raise NameError.
        expect(mod.instance_variable_defined?(:@_included_block)).to be true
      end
    end

    it "removes @_included_block when block source matches the target absolute path" do
      Dir.mktmpdir("evilution_concern_clean") do |dir|
        target_path = File.join(dir, "concern.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        mod.instance_variable_set(:@_included_block, block_at(target_path))

        cleaner.call(target_path)

        expect(mod.instance_variable_defined?(:@_included_block)).to be false
      end
    end

    it "removes @_prepended_block similarly" do
      Dir.mktmpdir("evilution_concern_prep") do |dir|
        target_path = File.join(dir, "concern_p.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        mod.instance_variable_set(:@_prepended_block, block_at(target_path))

        cleaner.call(target_path)

        expect(mod.instance_variable_defined?(:@_prepended_block)).to be false
      end
    end

    it "expands a relative target path before matching" do
      Dir.mktmpdir("evilution_concern_rel") do |dir|
        target_path = File.join(dir, "concern_rel.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        mod.instance_variable_set(:@_included_block, block_at(target_path))

        Dir.chdir(dir) do
          # Passing a relative path only matches if File.expand_path is applied.
          cleaner.call("concern_rel.rb")
        end

        expect(mod.instance_variable_defined?(:@_included_block)).to be false
      end
    end

    it "keeps state for modules whose block was declared elsewhere" do
      Dir.mktmpdir("evilution_concern_keep") do |dir|
        target_path = File.join(dir, "concern_keep.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        mod.instance_variable_set(:@_included_block, block_at("/some/other/file.rb"))

        cleaner.call(target_path)

        expect(mod.instance_variable_defined?(:@_included_block)).to be true
      end
    end

    it "leaves non-concern modules untouched" do
      Dir.mktmpdir("evilution_concern_nonconcern") do |dir|
        target_path = File.join(dir, "concern_skip.rb")
        File.write(target_path, "")

        plain = Module.new
        # Not extended with ActiveSupport::Concern, but carries an ivar that
        # would match by path. The concern-ancestry guard must skip it.
        plain.instance_variable_set(:@_included_block, block_at(target_path))

        cleaner.call(target_path)

        expect(plain.instance_variable_defined?(:@_included_block)).to be true
      end
    end

    it "matches via LOAD_PATH subpath when block source uses a relative-looking require path" do
      Dir.mktmpdir("evilution_concern_lp") do |dir|
        sub = File.join(dir, "lib")
        FileUtils.mkdir_p(sub)
        target_path = File.join(sub, "mypkg/mymod.rb")
        FileUtils.mkdir_p(File.dirname(target_path))
        File.write(target_path, "")
        $LOAD_PATH.unshift(sub)

        begin
          mod = Module.new
          mod.extend(ActiveSupport::Concern)
          mod.instance_variable_set(
            :@_included_block, block_at("/some/other/prefix/mypkg/mymod.rb")
          )

          cleaner.call(target_path)

          expect(mod.instance_variable_defined?(:@_included_block)).to be false
        ensure
          $LOAD_PATH.delete(sub)
        end
      end
    end

    it "does not remove a block whose subpath only partially matches" do
      Dir.mktmpdir("evilution_concern_partial") do |dir|
        sub = File.join(dir, "lib")
        FileUtils.mkdir_p(sub)
        target_path = File.join(sub, "mypkg/mymod.rb")
        FileUtils.mkdir_p(File.dirname(target_path))
        File.write(target_path, "")
        $LOAD_PATH.unshift(sub)

        begin
          mod = Module.new
          mod.extend(ActiveSupport::Concern)
          # subpath is "mypkg/mymod.rb"; this block path does not end with
          # "/mypkg/mymod.rb" nor equal the absolute target.
          mod.instance_variable_set(
            :@_included_block, block_at("/elsewhere/other_mod.rb")
          )

          cleaner.call(target_path)

          expect(mod.instance_variable_defined?(:@_included_block)).to be true
        ensure
          $LOAD_PATH.delete(sub)
        end
      end
    end
  end

  describe "ivar handling per concern module" do
    it "ignores concern modules that have neither tracked ivar set" do
      Dir.mktmpdir("evilution_concern_noivar") do |dir|
        target_path = File.join(dir, "concern_noivar.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)

        # No @_included_block / @_prepended_block set. instance_variable_get on
        # an undefined ivar would return nil and break source_location lookup
        # if the `instance_variable_defined?` guard were dropped.
        expect { cleaner.call(target_path) }.not_to raise_error
      end
    end

    it "ignores concern modules whose block reports no source location" do
      Dir.mktmpdir("evilution_concern_nosrc") do |dir|
        target_path = File.join(dir, "concern_nosrc.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        # A proc built from a C-defined method has a nil source_location.
        c_backed = [].method(:push).to_proc
        expect(c_backed.source_location).to be_nil
        mod.instance_variable_set(:@_included_block, c_backed)

        expect { cleaner.call(target_path) }.not_to raise_error
        expect(mod.instance_variable_defined?(:@_included_block)).to be true
      end
    end
  end
end
