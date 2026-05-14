# frozen_string_literal: true

require "evilution/integration/loading/body_call_neutralizer"

RSpec.describe Evilution::Integration::Loading::BodyCallNeutralizer do
  subject(:neutralizer) { described_class.new }

  def neutralize(src)
    neutralizer.call(src)
  end

  describe "#call" do
    it "replaces a registry-style call inside a module body with nil" do
      src = <<~RUBY
        module Foo
          register_mixin :bar, Baz
        end
      RUBY

      expect(neutralize(src)).to include("nil")
      expect(neutralize(src)).not_to include("register_mixin")
    end

    it "preserves include/extend/prepend (idempotent in Ruby)" do
      src = <<~RUBY
        class Foo
          include SomeMixin
          extend Other
          prepend Third
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("include SomeMixin")
      expect(result).to include("extend Other")
      expect(result).to include("prepend Third")
    end

    it "preserves attr_reader/attr_writer/attr_accessor (idempotent)" do
      src = <<~RUBY
        class Foo
          attr_reader :a
          attr_writer :b
          attr_accessor :c
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("attr_reader :a")
      expect(result).to include("attr_writer :b")
      expect(result).to include("attr_accessor :c")
    end

    it "preserves visibility modifiers (private/public/protected/module_function)" do
      src = <<~RUBY
        class Foo
          private
          def x; end
          public :x
          protected
          module_function :x
        end
      RUBY

      result = neutralize(src)
      %w[private public protected module_function].each do |kw|
        expect(result).to include(kw)
      end
    end

    it "preserves alias and alias_method, define_method/define_singleton_method" do
      src = <<~RUBY
        class Foo
          def x; end
          alias y x
          alias_method :z, :x
          define_method(:dm) { 1 }
          define_singleton_method(:dsm) { 2 }
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("alias y x")
      expect(result).to include("alias_method")
      expect(result).to include("define_method")
      expect(result).to include("define_singleton_method")
    end

    it "preserves method definitions and constant assignments" do
      src = <<~RUBY
        class Foo
          K = 1
          def bar
            register_mixin :nope  # inside method body — must not be neutralized
          end
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("K = 1")
      expect(result).to include("def bar")
      expect(result).to include("register_mixin :nope")
    end

    it "neutralizes a non-allowlisted top-level call at module scope" do
      src = <<~RUBY
        module Plugins
          register :foo, FooImpl
          configure! :bar
        end
      RUBY

      result = neutralize(src)
      expect(result).not_to include("register :foo")
      expect(result).not_to include("configure! :bar")
    end

    it "neutralizes setter-style assignment-call only when it is a method call (self.thing = ...)" do
      src = <<~RUBY
        class Foo
          self.timeout = 30
          @@cache = {}
        end
      RUBY

      result = neutralize(src)
      # `self.timeout=` is a method call → neutralized
      expect(result).not_to include("self.timeout = 30")
      # @@cache assignment is not a CallNode — preserved
      expect(result).to include("@@cache")
    end

    it "leaves source untouched when nothing to neutralize" do
      src = <<~RUBY
        class Foo
          K = 1
          attr_reader :x
          def bar; end
        end
      RUBY

      expect(neutralize(src)).to eq(src)
    end

    it "returns source unchanged when Prism parse fails" do
      bad = "class Foo\n  def x"
      expect(neutralize(bad)).to eq(bad)
    end

    it "preserves nested class bodies and neutralizes their non-allowlisted calls too" do
      src = <<~RUBY
        module Outer
          register_outer :x
          class Inner
            register_inner :y
            def m; register_inside; end
          end
        end
      RUBY

      result = neutralize(src)
      expect(result).not_to include("register_outer :x")
      expect(result).not_to include("register_inner :y")
      expect(result).to include("register_inside")
    end

    it "produces parseable output when neutralized call has a heredoc argument" do
      src = <<~SRC
        module Foo
          def_callback :send,
                       :node_or_nil_child,
                       :literal_child,
                       body: <<~CODE
                         node.children.each { |child| send(:on, child) }
                       CODE
        end
      SRC

      result = neutralize(src)
      parse = Prism.parse(result)

      expect(parse.failure?).to eq(false),
                                "neutralized source did not parse: #{parse.errors.map(&:message).join(", ")}\n#{result}"
      expect(result).not_to include("def_callback")
      expect(result).not_to include("node.children.each")
    end

    it "handles multi-line heredoc body and trailing call args together" do
      src = <<~SRC
        class Plugin
          register :foo, body: <<~CODE, name: "qux"
            puts "should be neutralized"
            puts "all of this"
          CODE
        end
      SRC

      result = neutralize(src)
      parse = Prism.parse(result)

      expect(parse.failure?).to eq(false),
                                "neutralized source did not parse: #{parse.errors.map(&:message).join(", ")}\n#{result}"
      expect(result).not_to include("register :foo")
      expect(result).not_to include("should be neutralized")
    end

    # EV-70hd / #1212: BodyCallNeutralizer's premise is "the parent already ran
    # this body during preload, so re-running side-effect calls in the child
    # would double-register." That premise breaks for lazy-loaded plugin files
    # (e.g. roda's typecast_params.rb) — the file is first-required INSIDE the
    # child fork, the parent has never run its DSL calls, and neutralizing
    # them strips method definitions that subsequent sibling statements depend
    # on (alias / etc.), cascading NameError.
    describe "lazy-load-aware skip" do
      let(:plugin_src) do
        <<~RUBY
          module Roda
            module Plugins
              module TypecastParams
                class Params
                  handle_type(:int) { |v| v.to_i }
                end
              end
            end
          end
        RUBY
      end

      after { described_class.reset_preload_snapshot! }

      it "neutralizes when the target file is in the preload snapshot" do
        described_class.preloaded_features = Set.new(["/preloaded/file.rb"])
        result = neutralizer.call(plugin_src, file_path: "/preloaded/file.rb")

        expect(result).not_to include("handle_type")
      end

      it "skips neutralization when the target file is NOT in the preload snapshot" do
        # Lazy-loaded plugin path: parent never ran it, child re-eval is the
        # file's FIRST execution. Stripping DSL calls here removes methods
        # other statements depend on. Skip — let the file load intact.
        described_class.preloaded_features = Set.new(["/other/file.rb"])
        result = neutralizer.call(plugin_src, file_path: "/lazy/plugin.rb")

        expect(result).to eq(plugin_src)
      end

      it "normalizes file paths so relative/absolute forms match the snapshot" do
        absolute = File.expand_path("lib/some_file.rb")
        described_class.preloaded_features = Set.new([absolute])
        result = neutralizer.call(plugin_src, file_path: "lib/some_file.rb")

        expect(result).not_to include("handle_type")
      end

      it "falls back to current behavior when file_path is not provided (backwards compat)" do
        # External callers that pass no file_path get the legacy
        # always-neutralize behavior. Existing internal callers will pass
        # file_path; this branch preserves any out-of-tree users.
        described_class.preloaded_features = Set.new([])
        result = neutralizer.call(plugin_src)

        expect(result).not_to include("handle_type")
      end

      it "returns a frozen lazy-init snapshot so fork COW pages are not broken by accidental mutation" do
        # Snapshot is shared across forks via copy-on-write. Mutating it would
        # both change neutralization semantics and force each child to copy the
        # backing page, defeating COW. Freezing the lazy-init result guards
        # against in-place mutation.
        described_class.reset_preload_snapshot!
        expect(described_class.preloaded_features).to be_frozen
      end
    end
  end
end
