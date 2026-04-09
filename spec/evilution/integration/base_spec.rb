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
  end

  describe "template #call orchestration" do
    let(:events) { [] }
    let(:hooks) { nil }

    let(:concrete_class) do
      ev = events
      Class.new(described_class) do
        define_method(:ensure_framework_loaded) { ev << :ensure_framework_loaded }
        define_method(:run_tests) { |_mutation| ev << :run_tests; { passed: false, test_command: "test" } }
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
      ev = events
      temp_dir_created = false
      failing_class = Class.new(described_class) do
        define_method(:ensure_framework_loaded) { nil }
        define_method(:run_tests) do |_mutation|
          temp_dir_created = !instance_variable_get(:@temp_dir).nil?
          raise "boom"
        end
        define_method(:build_args) { |_mutation| [] }
        define_method(:reset_state) { nil }
      end

      expect { failing_class.new.call(mutation) }.to raise_error(RuntimeError, "boom")
      expect(temp_dir_created).to be true
    end

    it "cleans up temp directory after call" do
      temp_dir_during = nil
      ev = events
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
    end
  end
end
