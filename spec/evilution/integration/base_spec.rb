# frozen_string_literal: true

require "tempfile"
require "evilution/integration/base"

RSpec.describe Evilution::Integration::Base do
  let(:source_file) { Tempfile.new(["base_target", ".rb"]) }
  let(:original_source) { "class Foo; end\n" }
  let(:mutated_source) { "class Bar; end\n" }

  let(:mutation) do
    double(
      "Mutation",
      file_path: source_file.path,
      original_source: original_source,
      mutated_source: mutated_source
    )
  end

  before do
    source_file.write(original_source)
    source_file.flush
  end

  after do
    source_file.close!
  end

  describe "abstract methods" do
    subject(:base) { described_class.new }

    it "raises NotImplementedError when subclass does not implement ensure_framework_loaded" do
      expect { base.call(mutation) }.to raise_error(
        NotImplementedError, /ensure_framework_loaded must be implemented/
      )
    end

    it "raises NotImplementedError for #run_tests" do
      expect { base.send(:run_tests, mutation) }.to raise_error(
        NotImplementedError, /run_tests must be implemented/
      )
    end

    it "raises NotImplementedError for #build_args" do
      expect { base.send(:build_args, mutation) }.to raise_error(
        NotImplementedError, /build_args must be implemented/
      )
    end

    it "raises NotImplementedError for #reset_state" do
      expect { base.send(:reset_state) }.to raise_error(
        NotImplementedError, /reset_state must be implemented/
      )
    end

    it "raises NotImplementedError for #ensure_framework_loaded" do
      expect { base.send(:ensure_framework_loaded) }.to raise_error(
        NotImplementedError, /ensure_framework_loaded must be implemented/
      )
    end

    it "raises NotImplementedError for .baseline_runner" do
      expect { described_class.baseline_runner }.to raise_error(
        NotImplementedError, /baseline_runner must be implemented/
      )
    end

    it "raises NotImplementedError for .baseline_options" do
      expect { described_class.baseline_options }.to raise_error(
        NotImplementedError, /baseline_options must be implemented/
      )
    end
  end

  describe "template #call orchestration" do
    let(:events) { [] }
    let(:hooks) { nil }

    let(:concrete_class) do
      ev = events
      Class.new(described_class) do
        define_method(:ensure_framework_loaded) { ev << :ensure_framework_loaded }
        define_method(:run_tests) do |_mutation|
          ev << :run_tests
          { passed: false, test_command: "test" }
        end
        define_method(:build_args) { |_mutation| [] }
        define_method(:reset_state) { nil }
      end
    end

    subject(:integration) { concrete_class.new(hooks: hooks) }

    it "calls ensure_framework_loaded before run_tests" do
      integration.call(mutation)

      expect(events).to eq(%i[ensure_framework_loaded run_tests])
    end

    it "applies mutation before running tests" do
      temp_dir_existed = false
      ev = events
      concrete_with_check = Class.new(described_class) do
        define_method(:ensure_framework_loaded) { nil }
        define_method(:run_tests) do |_mutation|
          temp_dir_existed = !instance_variable_get(:@temp_dir).nil?
          ev << :run_tests
          { passed: false, test_command: "test" }
        end
        define_method(:build_args) { |_mutation| [] }
        define_method(:reset_state) { nil }
      end

      concrete_with_check.new.call(mutation)

      expect(temp_dir_existed).to be true
    end

    it "restores original state even when run_tests raises" do
      temp_dir_during = nil
      failing_class = Class.new(described_class) do
        define_method(:ensure_framework_loaded) { nil }
        define_method(:run_tests) do |_mutation|
          temp_dir_during = instance_variable_get(:@temp_dir)
          raise "boom"
        end
        define_method(:build_args) { |_mutation| [] }
        define_method(:reset_state) { nil }
      end

      expect { failing_class.new.call(mutation) }.to raise_error(RuntimeError, "boom")
      expect(temp_dir_during).not_to be_nil
      expect(Dir.exist?(temp_dir_during)).to be false
    end

    it "cleans up temp directory after call" do
      temp_dir_during = nil
      tracking_class = Class.new(described_class) do
        define_method(:ensure_framework_loaded) { nil }
        define_method(:run_tests) do |_mutation|
          temp_dir_during = instance_variable_get(:@temp_dir)
          { passed: true, test_command: "test" }
        end
        define_method(:build_args) { |_mutation| [] }
        define_method(:reset_state) { nil }
      end

      tracking_class.new.call(mutation)

      expect(temp_dir_during).not_to be_nil
      expect(Dir.exist?(temp_dir_during)).to be false
    end

    it "returns the result from run_tests" do
      result = integration.call(mutation)

      expect(result).to eq({ passed: false, test_command: "test" })
    end

    context "with hooks" do
      let(:hooks) do
        Evilution::Hooks::Registry.new.tap do |h|
          h.register(:mutation_insert_pre) { events << :pre_hook }
          h.register(:mutation_insert_post) { events << :post_hook }
        end
      end

      it "fires hooks in correct order around mutation application" do
        integration.call(mutation)

        expect(events).to eq(%i[ensure_framework_loaded pre_hook post_hook run_tests])
      end
    end

    context "without hooks" do
      it "works without hooks" do
        result = integration.call(mutation)

        expect(result[:passed]).to be false
      end
    end
  end

  describe "mutation application" do
    let(:concrete_class) do
      Class.new(described_class) do
        define_method(:ensure_framework_loaded) { nil }
        define_method(:run_tests) { |_mutation| { passed: true, test_command: "test" } }
        define_method(:build_args) { |_mutation| [] }
        define_method(:reset_state) { nil }
      end
    end

    subject(:integration) { concrete_class.new }

    it "does not modify the original file" do
      integration.call(mutation)

      expect(File.read(source_file.path)).to eq(original_source)
    end

    context "with LOAD_PATH file" do
      let(:load_path_dir) { Dir.mktmpdir("evilution_base_lp") }
      let(:source_path) { File.join(load_path_dir, "target.rb") }

      let(:lp_mutation) do
        double(
          "Mutation",
          file_path: source_path,
          original_source: original_source,
          mutated_source: mutated_source
        )
      end

      before do
        File.write(source_path, original_source)
        $LOAD_PATH.unshift(load_path_dir)
      end

      after do
        $LOAD_PATH.delete(load_path_dir)
        FileUtils.rm_rf(load_path_dir)
      end

      it "shadows the file via LOAD_PATH prepend" do
        load_path_shadowed = false
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            temp_dir = instance_variable_get(:@temp_dir)
            load_path_shadowed = $LOAD_PATH.first == temp_dir
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        checking_class.new.call(lp_mutation)

        expect(load_path_shadowed).to be true
      end

      it "removes temp dir from LOAD_PATH after call" do
        load_path_before = $LOAD_PATH.dup

        integration.call(lp_mutation)

        new_entries = $LOAD_PATH - load_path_before
        expect(new_entries).to be_empty
      end

      it "loads the mutated source into memory" do
        original = "module EvilutionTestLpLoad; def self.value; :original; end; end\n"
        mutated = "module EvilutionTestLpLoad; def self.value; :mutated; end; end\n"
        File.write(source_path, original)
        load(source_path)

        lp_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        value_during_test = nil
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            value_during_test = EvilutionTestLpLoad.value
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        checking_class.new.call(lp_mut)

        expect(value_during_test).to eq(:mutated)
      ensure
        Object.send(:remove_const, :EvilutionTestLpLoad) if defined?(EvilutionTestLpLoad)
      end

      it "loads the mutated source when class is already defined (autoloader scenario)" do
        original = "module EvilutionTestAutoload; def self.value; :original; end; end\n"
        mutated = "module EvilutionTestAutoload; def self.value; :mutated; end; end\n"
        File.write(source_path, original)
        load(source_path)
        # Simulate autoloader: class is defined AND file is in $LOADED_FEATURES
        $LOADED_FEATURES << source_path unless $LOADED_FEATURES.include?(source_path)

        lp_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        value_during_test = nil
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            value_during_test = EvilutionTestAutoload.value
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        checking_class.new.call(lp_mut)

        expect(value_during_test).to eq(:mutated)
      ensure
        Object.send(:remove_const, :EvilutionTestAutoload) if defined?(EvilutionTestAutoload)
        $LOADED_FEATURES.delete(source_path)
      end

      it "returns error result when mutated source has a syntax error" do
        original = "module EvilutionTestSyntax; def self.value; :original; end; end\n"
        invalid = "module EvilutionTestSyntax; def self.value; :mutated; end; end; )\n"
        File.write(source_path, original)
        load(source_path)

        lp_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: invalid
        )

        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        result = checking_class.new.call(lp_mut)

        expect(result[:passed]).to be false
        expect(result[:error]).to match(/syntax error/)
      ensure
        Object.send(:remove_const, :EvilutionTestSyntax) if defined?(EvilutionTestSyntax)
      end

      it "rejects syntactically invalid mutated source via Prism before loading" do
        original = "module EvilutionTestPrismPre; def self.value; :original; end; end\n"
        invalid = "module EvilutionTestPrismPre; def self.value; :mutated; end; end; )\n"
        File.write(source_path, original)
        load(source_path)

        lp_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: invalid
        )

        run_tests_called = false
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            run_tests_called = true
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        result = checking_class.new.call(lp_mut)

        expect(result[:passed]).to be false
        expect(result[:error]).to eq("mutated source has syntax errors")
        expect(result[:error_class]).to eq("SyntaxError")
        expect(run_tests_called).to be false
      ensure
        Object.send(:remove_const, :EvilutionTestPrismPre) if defined?(EvilutionTestPrismPre)
      end

      it "does not create a temp dir when Prism rejects the source" do
        original = "module EvilutionTestPrismNoWrite; def self.value; :original; end; end\n"
        invalid = "module EvilutionTestPrismNoWrite; def self.(\n"
        File.write(source_path, original)
        load(source_path)

        lp_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: invalid
        )

        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) { |_mutation| { passed: true, test_command: "test" } }
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        allow(Dir).to receive(:mktmpdir).and_call_original

        checking_class.new.call(lp_mut)

        expect(Dir).not_to have_received(:mktmpdir).with("evilution")
      ensure
        Object.send(:remove_const, :EvilutionTestPrismNoWrite) if defined?(EvilutionTestPrismNoWrite)
      end

      it "returns error result when mutated source raises at load time" do
        original = "module EvilutionTestLoadErr; def self.value; :original; end; end\n"
        invalid = "module EvilutionTestLoadErr; super; end\n"
        File.write(source_path, original)
        load(source_path)

        lp_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: invalid
        )

        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        result = checking_class.new.call(lp_mut)

        expect(result[:passed]).to be false
        expect(result[:error]).to match(/super called outside of method/)
      ensure
        Object.send(:remove_const, :EvilutionTestLoadErr) if defined?(EvilutionTestLoadErr)
      end
    end

    context "with ActiveSupport::Concern modules" do
      let(:load_path_dir) { Dir.mktmpdir("evilution_base_concern") }
      let(:source_path) { File.join(load_path_dir, "concern_target.rb") }

      let(:concrete_class) do
        Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) { |_mutation| { passed: true, test_command: "test" } }
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end
      end

      before do
        $LOAD_PATH.unshift(load_path_dir)
      end

      after do
        $LOAD_PATH.delete(load_path_dir)
        FileUtils.rm_rf(load_path_dir)
      end

      it "clears @_included_block before re-evaluating a Concern module" do
        # Minimal ActiveSupport::Concern stub that replicates the guard behavior
        stub_concern = Module.new do
          def self.extended(base)
            base.instance_variable_set(:@_not_a_concern, false)
          end

          def included(base = nil, &block)
            if base.nil?
              if instance_variable_defined?(:@_included_block)
                if @_included_block.source_location != block.source_location
                  raise "MultipleIncludedBlocks: Cannot define multiple 'included' blocks for a Concern"
                end
              else
                @_included_block = block
              end
            else
              super(base)
            end
          end
        end
        stub_const("ActiveSupport::Concern", stub_concern)

        original = <<~RUBY
          module EvilutionTestConcern
            extend ActiveSupport::Concern

            included do
              # setup callback
            end

            def some_method
              :original
            end
          end
        RUBY
        mutated = <<~RUBY
          module EvilutionTestConcern
            extend ActiveSupport::Concern

            included do
              # setup callback
            end

            def some_method
              nil
            end
          end
        RUBY

        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        concern_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        result = concrete_class.new.call(concern_mut)

        expect(result[:passed]).to be true
        expect(result[:error]).to be_nil
      ensure
        Object.send(:remove_const, :EvilutionTestConcern) if defined?(EvilutionTestConcern)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end

      it "handles consecutive mutations of the same Concern (included block)" do
        stub_concern = Module.new do
          def self.extended(base)
            base.instance_variable_set(:@_not_a_concern, false)
          end

          def included(base = nil, &block)
            if base.nil?
              if instance_variable_defined?(:@_included_block)
                if @_included_block.source_location != block.source_location
                  raise "MultipleIncludedBlocks: Cannot define multiple 'included' blocks for a Concern"
                end
              else
                @_included_block = block
              end
            else
              super(base)
            end
          end
        end
        stub_const("ActiveSupport::Concern", stub_concern)

        original = <<~RUBY
          module EvilutionTestConcernConsec
            extend ActiveSupport::Concern

            included do
              # setup callback
            end

            def some_method
              :original
            end
          end
        RUBY
        mutated = <<~RUBY
          module EvilutionTestConcernConsec
            extend ActiveSupport::Concern

            included do
              # setup callback
            end

            def some_method
              nil
            end
          end
        RUBY

        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        concern_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        integration = concrete_class.new

        result1 = integration.call(concern_mut)
        expect(result1[:passed]).to be true
        expect(result1[:error]).to be_nil

        result2 = integration.call(concern_mut)
        expect(result2[:passed]).to be true
        expect(result2[:error]).to be_nil
      ensure
        Object.send(:remove_const, :EvilutionTestConcernConsec) if defined?(EvilutionTestConcernConsec)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end

      it "clears @_prepended_block before re-evaluating a Concern module" do
        stub_concern = Module.new do
          def self.extended(base)
            base.instance_variable_set(:@_not_a_concern, false)
          end

          def prepended(base = nil, &block)
            if base.nil?
              if instance_variable_defined?(:@_prepended_block)
                if @_prepended_block.source_location != block.source_location
                  raise "MultiplePrependedBlocks: Cannot define multiple 'prepended' blocks for a Concern"
                end
              else
                @_prepended_block = block
              end
            else
              super(base)
            end
          end
        end
        stub_const("ActiveSupport::Concern", stub_concern)

        original = <<~RUBY
          module EvilutionTestPrepended
            extend ActiveSupport::Concern

            prepended do
              # setup callback
            end

            def some_method
              :original
            end
          end
        RUBY
        mutated = <<~RUBY
          module EvilutionTestPrepended
            extend ActiveSupport::Concern

            prepended do
              # setup callback
            end

            def some_method
              nil
            end
          end
        RUBY

        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        concern_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        result = concrete_class.new.call(concern_mut)

        expect(result[:passed]).to be true
        expect(result[:error]).to be_nil
      ensure
        Object.send(:remove_const, :EvilutionTestPrepended) if defined?(EvilutionTestPrepended)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end

      it "handles consecutive mutations of the same Concern (prepended block)" do
        stub_concern = Module.new do
          def self.extended(base)
            base.instance_variable_set(:@_not_a_concern, false)
          end

          def prepended(base = nil, &block)
            if base.nil?
              if instance_variable_defined?(:@_prepended_block)
                if @_prepended_block.source_location != block.source_location
                  raise "MultiplePrependedBlocks: Cannot define multiple 'prepended' blocks for a Concern"
                end
              else
                @_prepended_block = block
              end
            else
              super(base)
            end
          end
        end
        stub_const("ActiveSupport::Concern", stub_concern)

        original = <<~RUBY
          module EvilutionTestPrependedConsec
            extend ActiveSupport::Concern

            prepended do
              # setup callback
            end

            def some_method
              :original
            end
          end
        RUBY
        mutated = <<~RUBY
          module EvilutionTestPrependedConsec
            extend ActiveSupport::Concern

            prepended do
              # setup callback
            end

            def some_method
              nil
            end
          end
        RUBY

        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        concern_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        integration = concrete_class.new

        result1 = integration.call(concern_mut)
        expect(result1[:passed]).to be true
        expect(result1[:error]).to be_nil

        result2 = integration.call(concern_mut)
        expect(result2[:passed]).to be true
        expect(result2[:error]).to be_nil
      ensure
        Object.send(:remove_const, :EvilutionTestPrependedConsec) if defined?(EvilutionTestPrependedConsec)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end

      it "pins constants before clear_concern_state to prevent Zeitwerk re-autoload" do
        # Zeitwerk's const_added hook can re-autoload the original file when
        # a module is reopened from a temp dir, re-setting @_included_block
        # after clear_concern_state already removed it.
        # The fix: pin constants via const_get before clearing and loading,
        # so Zeitwerk considers them already loaded and skips re-autoload.
        stub_concern = Module.new do
          def self.extended(base)
            base.instance_variable_set(:@_not_a_concern, false)
          end

          def included(base = nil, &block)
            if base.nil?
              if instance_variable_defined?(:@_included_block)
                if @_included_block.source_location != block.source_location
                  raise "MultipleIncludedBlocks: Cannot define multiple 'included' blocks for a Concern"
                end
              else
                @_included_block = block
              end
            else
              super(base)
            end
          end
        end
        stub_const("ActiveSupport::Concern", stub_concern)

        original = <<~RUBY
          module EvilutionTestZeitwerk
            extend ActiveSupport::Concern

            included do
              # setup callback
            end

            def some_method
              :original
            end
          end
        RUBY
        mutated = <<~RUBY
          module EvilutionTestZeitwerk
            extend ActiveSupport::Concern

            included do
              # setup callback
            end

            def some_method
              nil
            end
          end
        RUBY

        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        # Track call ordering: pin must happen before clear_concern_state
        call_order = []
        ordering_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) { |_mutation| { passed: true, test_command: "test" } }
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }

          define_method(:pin_autoloaded_constants) do |source|
            super(source).tap { |result| call_order << [:pin, result] }
          end

          define_method(:clear_concern_state) do |fp|
            call_order << [:clear]
            super(fp)
          end
        end

        concern_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        result = ordering_class.new.call(concern_mut)

        expect(result[:passed]).to be true
        expect(result[:error]).to be_nil

        # Verify pin runs before clear
        expect(call_order.map(&:first)).to eq(%i[pin clear])
        expect(call_order.first[1]).to include("EvilutionTestZeitwerk")
      ensure
        Object.send(:remove_const, :EvilutionTestZeitwerk) if defined?(EvilutionTestZeitwerk)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end

      it "pins nested and multiple constants from source" do
        original = <<~RUBY
          module EvilutionTestOuter
            class EvilutionTestInner
              def value
                :original
              end
            end
          end
        RUBY
        mutated = <<~RUBY
          module EvilutionTestOuter
            class EvilutionTestInner
              def value
                nil
              end
            end
          end
        RUBY

        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        pin_calls = []
        pinning_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) { |_mutation| { passed: true, test_command: "test" } }
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }

          define_method(:pin_autoloaded_constants) do |source|
            super(source).tap { |result| pin_calls << result }
          end
        end

        pin_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        pinning_class.new.call(pin_mut)

        expect(pin_calls.first).to include("EvilutionTestOuter")
        expect(pin_calls.first).to include("EvilutionTestOuter::EvilutionTestInner")
      ensure
        Object.send(:remove_const, :EvilutionTestOuter) if defined?(EvilutionTestOuter)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end

      it "does not affect modules that are not ActiveSupport::Concern" do
        original = "module EvilutionTestNonConcern; def self.value; :original; end; end\n"
        mutated = "module EvilutionTestNonConcern; def self.value; :mutated; end; end\n"
        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        non_concern_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        value_during_test = nil
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            value_during_test = EvilutionTestNonConcern.value
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        checking_class.new.call(non_concern_mut)

        expect(value_during_test).to eq(:mutated)
      ensure
        Object.send(:remove_const, :EvilutionTestNonConcern) if defined?(EvilutionTestNonConcern)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end
    end

    context "with absolute path file (not under LOAD_PATH)" do
      let(:isolated_dir) { Dir.mktmpdir("evilution_base_abs") }
      let(:source_path) { File.join(isolated_dir, "abs_target.rb") }

      after do
        FileUtils.rm_rf(isolated_dir)
      end

      it "loads the mutated source into memory" do
        original = "module EvilutionTestAbsLoad; def self.value; :original; end; end\n"
        mutated = "module EvilutionTestAbsLoad; def self.value; :mutated; end; end\n"
        File.write(source_path, original)
        load(source_path)

        abs_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        value_during_test = nil
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            value_during_test = EvilutionTestAbsLoad.value
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        checking_class.new.call(abs_mut)

        expect(value_during_test).to eq(:mutated)
      ensure
        Object.send(:remove_const, :EvilutionTestAbsLoad) if defined?(EvilutionTestAbsLoad)
      end
    end

    context "with a DSL that rejects re-definition (e.g. Rails 8 enum)" do
      let(:load_path_dir) { Dir.mktmpdir("evilution_base_define_once") }
      let(:source_path) { File.join(load_path_dir, "define_once_target.rb") }

      before do
        $LOAD_PATH.unshift(load_path_dir)
      end

      after do
        $LOAD_PATH.delete(load_path_dir)
        FileUtils.rm_rf(load_path_dir)
      end

      it "retries the load on a fresh constant when the class body raises a redefinition conflict" do
        dsl_module = Module.new do
          def define_once(name)
            raise ArgumentError, "#{name} is already defined on #{self}" if method_defined?(name)

            define_method(name) { :dsl }
          end
        end
        stub_const("EvilutionTestDefineOnce", dsl_module)

        original = <<~RUBY
          class EvilutionTestEnumLike
            extend EvilutionTestDefineOnce
            define_once :predicate
            def payload; :original; end
          end
        RUBY
        mutated = <<~RUBY
          class EvilutionTestEnumLike
            extend EvilutionTestDefineOnce
            define_once :predicate
            def payload; :mutated; end
          end
        RUBY

        File.write(source_path, original)
        load(source_path)
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        enum_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        captured = {}
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            instance = EvilutionTestEnumLike.new
            captured[:payload] = instance.payload
            captured[:predicate] = instance.predicate
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        result = checking_class.new.call(enum_mut)

        expect(result[:error]).to be_nil
        expect(captured[:payload]).to eq(:mutated)
        expect(captured[:predicate]).to eq(:dsl)
      ensure
        Object.send(:remove_const, :EvilutionTestEnumLike) if defined?(EvilutionTestEnumLike)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end

      it "preserves constant object identity when the load succeeds without conflict" do
        original = "module EvilutionTestNoConflict; def self.value; :original; end; end\n"
        mutated = "module EvilutionTestNoConflict; def self.value; :mutated; end; end\n"
        File.write(source_path, original)
        load(source_path)
        original_object_id = EvilutionTestNoConflict.object_id
        $LOADED_FEATURES << File.expand_path(source_path) unless $LOADED_FEATURES.include?(File.expand_path(source_path))

        no_conflict_mut = double(
          "Mutation",
          file_path: source_path,
          original_source: original,
          mutated_source: mutated
        )

        captured = {}
        checking_class = Class.new(described_class) do
          define_method(:ensure_framework_loaded) { nil }
          define_method(:run_tests) do |_mutation|
            captured[:object_id] = EvilutionTestNoConflict.object_id
            captured[:value] = EvilutionTestNoConflict.value
            { passed: true, test_command: "test" }
          end
          define_method(:build_args) { |_mutation| [] }
          define_method(:reset_state) { nil }
        end

        checking_class.new.call(no_conflict_mut)

        expect(captured[:value]).to eq(:mutated)
        expect(captured[:object_id]).to eq(original_object_id)
      ensure
        Object.send(:remove_const, :EvilutionTestNoConflict) if defined?(EvilutionTestNoConflict)
        $LOADED_FEATURES.delete(File.expand_path(source_path))
      end
    end
  end
end
