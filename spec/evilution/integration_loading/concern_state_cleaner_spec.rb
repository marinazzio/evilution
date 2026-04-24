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

  describe "#call" do
    it "returns without error when ActiveSupport::Concern is undefined" do
      concern = ActiveSupport.send(:remove_const, :Concern)
      begin
        expect { cleaner.call("/tmp/absent.rb") }.not_to raise_error
      ensure
        ActiveSupport.const_set(:Concern, concern)
      end
    end

    it "removes @_included_block when block source matches the target absolute path" do
      Dir.mktmpdir("evilution_concern_clean") do |dir|
        target_path = File.join(dir, "concern.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        block = eval("proc {}", TOPLEVEL_BINDING, target_path, 1) # rubocop:disable Style/EvalWithLocation
        mod.instance_variable_set(:@_included_block, block)

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
        block = eval("proc {}", TOPLEVEL_BINDING, target_path, 1) # rubocop:disable Style/EvalWithLocation
        mod.instance_variable_set(:@_prepended_block, block)

        cleaner.call(target_path)

        expect(mod.instance_variable_defined?(:@_prepended_block)).to be false
      end
    end

    it "keeps state for modules whose block was declared elsewhere" do
      Dir.mktmpdir("evilution_concern_keep") do |dir|
        target_path = File.join(dir, "concern_keep.rb")
        File.write(target_path, "")

        mod = Module.new
        mod.extend(ActiveSupport::Concern)
        block = eval("proc {}", TOPLEVEL_BINDING, "/some/other/file.rb", 1) # rubocop:disable Style/EvalWithLocation
        mod.instance_variable_set(:@_included_block, block)

        cleaner.call(target_path)

        expect(mod.instance_variable_defined?(:@_included_block)).to be true
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
          block = eval("proc {}", TOPLEVEL_BINDING, "/some/other/prefix/mypkg/mymod.rb", 1) # rubocop:disable Style/EvalWithLocation
          mod.instance_variable_set(:@_included_block, block)

          cleaner.call(target_path)

          expect(mod.instance_variable_defined?(:@_included_block)).to be false
        ensure
          $LOAD_PATH.delete(sub)
        end
      end
    end
  end
end
