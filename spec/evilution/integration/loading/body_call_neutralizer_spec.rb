# frozen_string_literal: true

require "prism"
require "evilution/integration/loading/body_call_neutralizer"

RSpec.describe Evilution::Integration::Loading::BodyCallNeutralizer do
  subject(:neutralizer) { described_class.new }

  def neutralize(src)
    neutralizer.call(src)
  end

  describe ".preloaded_features" do
    after { described_class.reset_preload_snapshot! }

    it "lazily initialises to a Set snapshot of $LOADED_FEATURES" do
      described_class.reset_preload_snapshot!
      already_loaded = $LOADED_FEATURES.first
      features = described_class.preloaded_features

      expect(features).to be_a(Set)
      # Membership mirrors $LOADED_FEATURES — already-loaded files are present.
      expect(features).to include(already_loaded)
    end

    it "returns a frozen snapshot so fork COW pages survive accidental mutation" do
      described_class.reset_preload_snapshot!
      expect(described_class.preloaded_features).to be_frozen
    end

    it "memoizes the snapshot across calls" do
      described_class.reset_preload_snapshot!
      first = described_class.preloaded_features
      expect(described_class.preloaded_features).to equal(first)
    end

    it "returns the assigned snapshot once preloaded_features= is set" do
      described_class.preloaded_features = Set.new(["/some/explicit.rb"])
      expect(described_class.preloaded_features).to eq(Set.new(["/some/explicit.rb"]))
    end
  end

  describe ".reset_preload_snapshot!" do
    after { described_class.reset_preload_snapshot! }

    it "clears a previously assigned snapshot so the next read re-initialises" do
      described_class.preloaded_features = Set.new(["/stale/file.rb"])
      described_class.reset_preload_snapshot!

      refreshed = described_class.preloaded_features
      expect(refreshed).not_to eq(Set.new(["/stale/file.rb"]))
      expect(refreshed).to be_a(Set)
    end
  end

  describe "#call with keep_offset" do
    let(:src) do
      <<~RUBY
        class Order
          scope :paid, -> { where(paid: true) }
          scope :open, -> { where(open: nil) }
        end
      RUBY
    end

    it "keeps the class-body call that contains the offset and neutralizes the others" do
      offset = src.index("nil")

      expect(neutralizer.call(src, keep_offset: offset))
        .to eq("class Order\n  ()\n  scope :open, -> { where(open: nil) }\nend\n")
    end

    it "keeps a call whose first byte is the offset" do
      offset = src.index("scope :open")

      expect(neutralizer.call(src, keep_offset: offset)).to include("scope :open")
    end

    it "neutralizes a call that ends just before the offset" do
      offset = src.index("}\n  scope :open") + 1

      expect(neutralizer.call(src, keep_offset: offset)).not_to include("scope :paid")
    end
  end

  describe "#call with keep_offset inside an aasm block" do
    let(:src) do
      <<~RUBY
        class Order
          validates :address, presence: true
          aasm column: :status do
            after_all_transitions :log
            state :paid, before_exit: -> { leaving }
            event :ship, guard: -> { address? } do
              transitions from: :paid, to: :shipped
            end
            event :cancel do
              transitions from: :paid, to: :paid
            end
          end
        end
      RUBY
    end

    it "keeps the machine call but only the event the offset is in" do
      expect(neutralizer.call(src, keep_offset: src.index("address?"))).to eq(<<~RUBY)
        class Order
          ()
          aasm column: :status do
            ()
            ()
            event :ship, guard: -> { address? } do
              transitions from: :paid, to: :shipped
            end
            ()


          end
        end
      RUBY
    end

    it "keeps only the state the offset is in" do
      result = neutralizer.call(src, keep_offset: src.index("leaving"))

      expect(result).to include("state :paid, before_exit: -> { leaving }")
      expect(result).not_to include("event")
      expect(result).not_to include("after_all_transitions")
    end

    it "leaves statements of the block that are not calls in place" do
      with_assignment = src.sub("after_all_transitions :log", "limit = 3")

      result = neutralizer.call(with_assignment, keep_offset: with_assignment.index("address?"))

      expect(result).to include("limit = 3")
    end

    it "neutralizes the whole machine when the offset is elsewhere" do
      result = neutralizer.call(src, keep_offset: src.index("validates"))

      expect(result).to eq("class Order\n  validates :address, presence: true\n  ()#{"\n" * 10}end\n")
      expect(result.lines.length).to eq(src.lines.length)
    end

    it "takes a heredoc of a neutralized sibling with it" do
      heredoc = src.sub("after_all_transitions :log", "note <<~TEXT\n      hello\n    TEXT")

      result = neutralizer.call(heredoc, keep_offset: heredoc.index("address?"))

      expect(result).not_to include("hello")
      expect(Prism.parse(result)).to be_success
    end
  end

  describe "#call with keep_offset inside a concern's included block" do
    let(:skipping) { "::Evilution::Integration::Loading::ConcernRedeclaration.skipping?" }
    let(:redeclare) { "::Evilution::Integration::Loading::ConcernRedeclaration.call(self)" }
    let(:src) do
      <<~RUBY
        module Publishable
          extend ActiveSupport::Concern
          register :publishable

          included do
            validates :title, presence: true
            limit = 3
            scope :published, -> { where(published: true) }
            scope :recent, -> { order(:id).limit(limit) }
          end

          def publish! = true
        end
      RUBY
    end

    it "keeps the block, guards its other calls and re-declares on the classes that include the concern" do
      expect(neutralizer.call(src, keep_offset: src.index("published: true"))).to eq(<<~RUBY)
        module Publishable
          extend ActiveSupport::Concern
          ()

          included do
            #{skipping} or validates :title, presence: true
            limit = 3
            scope :published, -> { where(published: true) }
            #{skipping} or scope :recent, -> { order(:id).limit(limit) }
          end; #{redeclare}

          def publish! = true
        end
      RUBY
    end

    it "keeps every line where it was" do
      result = neutralizer.call(src, keep_offset: src.index("published: true"))

      expect(result.lines.length).to eq(src.lines.length)
      expect(Prism.parse(result)).to be_success
    end

    it "neutralizes the whole block when the offset is elsewhere" do
      result = neutralizer.call(src, keep_offset: src.index("register"))

      expect(result).not_to include("included")
      expect(result).to include("register :publishable")
    end

    it "treats a kept call that only looks like an included block as any other" do
      plain = "class Order\n  included(base) do\n    scope :a, -> { nil }\n  end\nend\n"

      expect(neutralizer.call(plain, keep_offset: plain.index("nil"))).to eq(plain)
    end
  end

  describe "#call with keep_offset inside a callback declaration" do
    let(:helper) { "::Evilution::Integration::Loading::CallbackRedeclaration.call" }
    let(:src) do
      <<~RUBY
        class Order
          before_save :first
          validate :credit_limit, if: -> { paid? } # why
          before_save do
            self.total = nil
          end
        end
      RUBY
    end

    it "wraps the declaration on its own line, with the lines it was loaded from" do
      result = neutralizer.call(src, keep_offset: src.index("paid?"), keep_lines: 3..3)

      expect(result).to eq(<<~RUBY)
        class Order
          ()
          #{helper}(self, __FILE__, 3..3) { validate :credit_limit, if: -> { paid? } } # why
          ()


        end
      RUBY
    end

    it "wraps a declaration with a do block and keeps every line where it was" do
      result = neutralizer.call(src, keep_offset: src.index("nil"), keep_lines: 4..6)

      expect(result.lines[3..5].join).to eq(
        "  #{helper}(self, __FILE__, 4..6) { before_save do\n    self.total = nil\n  end }\n"
      )
      expect(result.lines.length).to eq(src.lines.length - 0)
      expect(Prism.parse(result)).to be_success
    end

    it "keeps the declaration unwrapped when no lines are given" do
      result = neutralizer.call(src, keep_offset: src.index("paid?"))

      expect(result).to include("  validate :credit_limit, if: -> { paid? } # why")
    end

    it "does not wrap a kept call that is not a callback declaration" do
      scopes = "class Order\n  scope :open, -> { nil }\nend\n"

      expect(neutralizer.call(scopes, keep_offset: scopes.index("nil"), keep_lines: 2..2)).to eq(scopes)
    end
  end

  describe "#call with keep_offset inside an aasm block of a concern's included block" do
    let(:skipping) { "::Evilution::Integration::Loading::ConcernRedeclaration.skipping?" }
    let(:redeclare) { "::Evilution::Integration::Loading::ConcernRedeclaration.call(self)" }
    let(:src) do
      <<~RUBY
        module Shippable
          extend ActiveSupport::Concern

          included do
            include AASM
            aasm column: :status do
              after_all_transitions :log
              state :paid, initial: true
              event :ship, guard: -> { address? } do
                transitions from: :paid, to: :shipped
              end
              event :cancel do
                transitions from: :paid, to: :paid
              end
            end
          end
        end
      RUBY
    end

    # A class that includes the concern later runs all of it, so nothing is
    # blanked; one that includes it already runs it again with every other
    # declaration skipped.
    it "guards the other statements of the block and the other declarations of the machine" do
      expect(neutralizer.call(src, keep_offset: src.index("address?"))).to eq(<<~RUBY)
        module Shippable
          extend ActiveSupport::Concern

          included do
            #{skipping} or include AASM
            aasm column: :status do
              #{skipping} or after_all_transitions :log
              #{skipping} or state :paid, initial: true
              event :ship, guard: -> { address? } do
                transitions from: :paid, to: :shipped
              end
              #{skipping} or event :cancel do
                transitions from: :paid, to: :paid
              end
            end
          end; #{redeclare}
        end
      RUBY
    end

    it "produces source that parses, with every line where it was" do
      result = neutralizer.call(src, keep_offset: src.index("address?"))

      expect(Prism.parse(result)).to be_success
      expect(result.lines.length).to eq(src.lines.length)
    end
  end

  describe "#call with keep_offset inside a callback declaration of a concern's included block" do
    let(:skipping) { "::Evilution::Integration::Loading::ConcernRedeclaration.skipping?" }
    let(:redeclare) { "::Evilution::Integration::Loading::ConcernRedeclaration.call(self)" }
    let(:callbacks) { "::Evilution::Integration::Loading::CallbackRedeclaration.call" }
    let(:src) do
      <<~RUBY
        module Publishable
          extend ActiveSupport::Concern

          included do
            before_save :first
            validates :title, presence: true, if: -> { published? }
            before_save :last
          end
        end
      RUBY
    end

    # Run on a class that includes the concern already, only the mutated
    # declaration runs, and its callbacks take the place of the old ones; run
    # by a class including it later, the whole block declares as written.
    it "wraps the declaration in place and guards the others" do
      expect(neutralizer.call(src, keep_offset: src.index("published?"), keep_lines: 6..6)).to eq(<<~RUBY)
        module Publishable
          extend ActiveSupport::Concern

          included do
            #{skipping} or before_save :first
            #{callbacks}(self, __FILE__, 6..6) { validates :title, presence: true, if: -> { published? } }
            #{skipping} or before_save :last
          end; #{redeclare}
        end
      RUBY
    end

    it "does not wrap it when no lines are given" do
      result = neutralizer.call(src, keep_offset: src.index("published?"))

      expect(result).to include("    validates :title, presence: true, if: -> { published? }\n")
    end

    it "does not wrap a kept scope of the block" do
      scopes = src.sub("validates :title, presence: true, if: -> { published? }", "scope :live, -> { nil }")

      result = neutralizer.call(scopes, keep_offset: scopes.index("nil"), keep_lines: 6..6)

      expect(result).to include("    scope :live, -> { nil }\n")
    end
  end

  describe "line numbers" do
    let(:src) do
      <<~RUBY
        class Order
          register :orders,
                   with: :defaults
          has_many :items, -> do
            where(visible: true)
          end

          def total = 1
        end
      RUBY
    end

    # A proc created by the evaluated source says where it was written by
    # that source's line numbers; they have to be the file's.
    it "leaves a blanked call's line breaks behind, so what follows keeps its line" do
      result = neutralizer.call(src)

      expect(result).to eq("class Order\n  ()\n\n  ()\n\n\n\n  def total = 1\nend\n")
      expect(result.lines.index("  def total = 1\n")).to eq(src.lines.index("  def total = 1\n"))
    end

    it "adds no line break for a call on a single line" do
      expect(neutralizer.call("class Order\n  register :orders\nend\n")).to eq("class Order\n  ()\nend\n")
    end
  end

  describe "#call" do
    it "replaces a registry-style call inside a module body with ()" do
      src = <<~RUBY
        module Foo
          register_mixin :bar, Baz
        end
      RUBY

      result = neutralize(src)
      expect(result).to eq("module Foo\n  ()\nend\n")
      expect(result).not_to include("register_mixin")
    end

    # Projects that run specs with --warnings and raise on every warning (dry-monads)
    # would otherwise fail each mutation of the file on "possibly useless use of nil
    # in void context", before any test runs.
    it "leaves nothing Ruby warns about as a void-context expression" do
      src = <<~RUBY
        class Foo
          deprecate :lift, :coerce
          def coerce; end
        end
      RUBY
      result = neutralize(src)

      previous = $VERBOSE
      $VERBOSE = true
      expect { RubyVM::InstructionSequence.compile(result) }.not_to output.to_stderr
    ensure
      $VERBOSE = previous
    end

    it "preserves include/extend/prepend/using (idempotent in Ruby)" do
      src = <<~RUBY
        class Foo
          include SomeMixin
          extend Other
          prepend Third
          using Refine
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("include SomeMixin")
      expect(result).to include("extend Other")
      expect(result).to include("prepend Third")
      expect(result).to include("using Refine")
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

    it "preserves private_class_method/public_class_method/autoload" do
      src = <<~RUBY
        class Foo
          private_class_method :a
          public_class_method :b
          autoload :C, "c"
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("private_class_method :a")
      expect(result).to include("public_class_method :b")
      expect(result).to include("autoload :C")
    end

    it "preserves alias_method, define_method/define_singleton_method, delegate" do
      src = <<~RUBY
        class Foo
          def x; end
          alias_method :z, :x
          define_method(:dm) { 1 }
          define_singleton_method(:dsm) { 2 }
          delegate :to_s, to: :x
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("alias_method")
      expect(result).to include("define_method")
      expect(result).to include("define_singleton_method")
      expect(result).to include("delegate :to_s")
    end

    it "preserves require/require_relative calls in the body" do
      src = <<~RUBY
        class Foo
          require "set"
          require_relative "thing"
        end
      RUBY

      result = neutralize(src)
      expect(result).to include('require "set"')
      expect(result).to include('require_relative "thing"')
    end

    it "preserves method definitions and constant assignments" do
      src = <<~RUBY
        class Foo
          K = 1
          def bar
            register_mixin :nope
          end
        end
      RUBY

      result = neutralize(src)
      expect(result).to include("K = 1")
      expect(result).to include("def bar")
      # A call inside a def body is NOT a direct child — must not be touched.
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

    it "neutralizes a setter-style call (self.thing = ...) but not non-call assignments" do
      src = <<~RUBY
        class Foo
          self.timeout = 30
          @@cache = {}
        end
      RUBY

      result = neutralize(src)
      # `self.timeout=` is a CallNode with a SelfNode receiver → neutralized.
      expect(result).not_to include("self.timeout = 30")
      # @@cache assignment is not a CallNode — preserved.
      expect(result).to include("@@cache")
    end

    it "leaves a call with a non-self receiver untouched" do
      src = <<~RUBY
        class Foo
          Registry.add(:x)
        end
      RUBY

      # Receiver is a constant, not self — scan_body skips it.
      expect(neutralize(src)).to include("Registry.add(:x)")
    end

    it "returns the exact same source object when there is nothing to neutralize" do
      src = +"class Foo\n  K = 1\n  attr_reader :x\n  def bar; end\nend\n"
      result = neutralize(src)

      # The empty-edits guard short-circuits with `return source` — the caller
      # gets the identical object back, not a re-encoded copy.
      expect(result).to equal(src)
    end

    it "returns source unchanged when Prism parse fails, even if a body call is present" do
      # A failed parse still yields a partial tree with neutralizable calls.
      # Without the failure guard the neutralizer would corrupt the source;
      # the guard must return the original bytes verbatim.
      bad = "class Foo\n  reg :x\n  def y"
      expect(neutralize(bad)).to eq(bad)
      expect(neutralize(bad)).to include("reg :x")
    end

    it "handles an empty class/module body without raising" do
      # An empty body's `node.body` is nil, not a StatementsNode. scan_body's
      # type guard must short-circuit; otherwise `nil.body.each` raises.
      src = <<~RUBY
        class Empty
        end

        module AlsoEmpty
        end
      RUBY

      expect { neutralize(src) }.not_to raise_error
      expect(neutralize(src)).to eq(src)
    end

    it "neutralizes a sibling call even when an empty class precedes it" do
      # Exercises scan_body reaching a nil-body node and a real one in the
      # same walk — the nil-body guard must not abort the whole scan.
      src = <<~RUBY
        module Host
          class Blank
          end
          side_effect :go
        end
      RUBY

      result = neutralize(src)
      expect(result).not_to include("side_effect")
      expect(result).to include("class Blank")
    end

    it "returns source unchanged at top level when no class/module wraps the call" do
      # A bare top-level call is not inside a class/module body — the walker
      # never scans it, so collect_edits is empty and source is returned as-is.
      src = "register :foo\n"
      expect(neutralize(src)).to eq(src)
    end

    it "preserves nested class bodies and neutralizes their non-allowlisted calls" do
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
      # The outer body call is neutralized.
      expect(result).not_to include("register_outer :x")
      # super recursion reaches the nested class body too.
      expect(result).not_to include("register_inner :y")
      # A call inside a def is still left alone.
      expect(result).to include("register_inside")
    end

    it "neutralizes calls inside a singleton class body via visit_singleton_class_node" do
      src = <<~RUBY
        class Foo
          class << self
            register_thing :x
          end
        end
      RUBY

      result = neutralize(src)
      expect(result).to eq("class Foo\n  class << self\n    ()\n  end\nend\n")
      expect(result).not_to include("register_thing")
    end

    it "recurses into a class nested inside a singleton class body" do
      # visit_singleton_class_node must call super so the visitor descends
      # into nested class/module nodes declared within `class << self`.
      src = <<~RUBY
        class Foo
          class << self
            class Nested
              register_nested :z
            end
          end
        end
      RUBY

      result = neutralize(src)
      expect(result).not_to include("register_nested")
      expect(result).to include("class Nested")
    end

    it "neutralizes a call inside a module body via visit_module_node" do
      src = "module M\n  side_effect :go\nend\n"
      expect(neutralize(src)).to eq("module M\n  ()\nend\n")
    end

    it "neutralizes a call inside a class body via visit_class_node" do
      src = "class C\n  side_effect :go\nend\n"
      expect(neutralize(src)).to eq("class C\n  ()\nend\n")
    end

    it "neutralizes every non-allowlisted body call, not just the first" do
      src = <<~RUBY
        module Multi
          first_call :a
          second_call :b
          third_call :c
        end
      RUBY

      result = neutralize(src)
      expect(result).not_to include("first_call")
      expect(result).not_to include("second_call")
      expect(result).not_to include("third_call")
      expect(result.scan("()").length).to eq(3)
    end

    it "applies edits in descending offset order so byte ranges do not shift" do
      # The inner class is declared BEFORE the outer sibling call, so the
      # walker collects the outer edit first and the (lower-offset) inner edit
      # second — edits arrive unsorted. apply_edits must sort and apply them
      # back-to-front; otherwise earlier replacements shift later offsets and
      # corrupt the output (or raise IndexError).
      src = <<~RUBY
        module Outer
          class Inner
            inner_call :longargumenthere
          end
          outer_call :x
        end
      RUBY

      result = neutralize(src)
      expect(result).to eq(<<~RUBY)
        module Outer
          class Inner
            ()
          end
          ()
        end
      RUBY
      expect(result).not_to include("inner_call")
      expect(result).not_to include("outer_call")
    end

    it "preserves the source string encoding through neutralization" do
      src = (+"module Foo\n  reg :x\nend\n").force_encoding("US-ASCII")
      result = neutralize(src)

      expect(result.encoding).to eq(Encoding::US_ASCII)
      expect(result).to eq("module Foo\n  ()\nend\n")
    end

    it "does not mutate the caller's source string in place" do
      src = +"module Foo\n  reg :x\nend\n"
      original = src.dup
      neutralize(src)

      expect(src).to eq(original)
    end

    describe "heredoc arguments" do
      it "produces parseable output and keeps `end` on its own line" do
        src = <<~SRC
          module Foo
            def_callback :send,
                         body: <<~CODE
                           node.children.each { |child| send(:on, child) }
                         CODE
          end
        SRC

        result = neutralize(src)
        parse = Prism.parse(result)

        expect(parse.failure?).to eq(false),
                                  "did not parse: #{parse.errors.map(&:message).join(", ")}\n#{result}"
        expect(result).not_to include("def_callback")
        expect(result).not_to include("node.children.each")
        # The heredoc terminator's trailing newline is excluded from the
        # replacement, so the `()` and the closing `end` stay on
        # separate lines (no `()end` collision).
        expect(result).to match(/^  \(\)\n+end$/)
        expect(result).not_to include("()end")
      end

      it "handles a multi-line heredoc body plus trailing call args together" do
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
                                  "did not parse: #{parse.errors.map(&:message).join(", ")}\n#{result}"
        expect(result).not_to include("register :foo")
        expect(result).not_to include("should be neutralized")
        expect(result).not_to include('name: "qux"')
        expect(result).not_to include("()end")
      end

      it "extends the replacement past a plain x-string (backtick) heredoc terminator" do
        # A `<<~`MARKER`` backtick heredoc argument is an XStringNode.
        # HeredocEndCollector#visit_x_string_node must call record_if_heredoc
        # so the replacement reaches the `CMD` terminator; otherwise the
        # heredoc body lines and terminator are left orphaned after the `()`.
        src = "module Foo\n  " \
              "run_cmd :build, <<~`CMD`\n    " \
              "echo building\n  " \
              "CMD\n" \
              "end\n"

        result = neutralize(src)

        expect(result).to eq("module Foo\n  ()\n\n\nend\n")
        expect(result).not_to include("run_cmd")
        expect(result).not_to include("echo building")
        expect(result).not_to include("CMD")
      end

      it "extends the replacement past an interpolated x-string heredoc terminator" do
        # A backtick heredoc carrying `#{...}` interpolation is an
        # InterpolatedXStringNode. visit_interpolated_x_string_node must call
        # record_if_heredoc so the replacement reaches the `CMD` terminator.
        src = "module Foo\n  " \
              "run_cmd :build, <<~`CMD`\n    " \
              "echo building \#{flag}\n  " \
              "CMD\n" \
              "end\n"

        result = neutralize(src)

        expect(result).to eq("module Foo\n  ()\n\n\nend\n")
        expect(result).not_to include("run_cmd")
        expect(result).not_to include("echo building")
        expect(result).not_to include("CMD")
      end

      it "recurses into a regular interpolated string to reach a nested trailing heredoc" do
        # The argument `"pre #{wrap(<<~H)} post"` is a non-heredoc
        # InterpolatedStringNode whose `#{...}` opens a heredoc. The heredoc
        # body trails AFTER the closing quote (and after the call's own end
        # offset), so visit_interpolated_string_node must call `super` to
        # descend into the interpolation and record the `H` terminator.
        src = "module Foo\n  " \
              "def_thing :a, \"pre \#{wrap(<<~H)} post\"\n    " \
              "heredoc body line\n  " \
              "H\n" \
              "end\n"

        result = neutralize(src)

        expect(result).to eq("module Foo\n  ()\n\n\nend\n")
        expect(result).not_to include("def_thing")
        expect(result).not_to include("heredoc body line")
      end

      it "recurses into a regular backtick command to reach a nested trailing heredoc" do
        # The argument `` `cmd #{wrap(<<~H)} tail` `` is a non-heredoc
        # InterpolatedXStringNode whose interpolation opens a heredoc whose
        # body trails after the closing backtick. visit_interpolated_x_string_node
        # must call `super` to descend and record the `H` terminator.
        src = "module Foo\n  " \
              "def_thing :a, `cmd \#{wrap(<<~H)} tail`\n    " \
              "heredoc body line\n  " \
              "H\n" \
              "end\n"

        result = neutralize(src)

        expect(result).to eq("module Foo\n  ()\n\n\nend\n")
        expect(result).not_to include("def_thing")
        expect(result).not_to include("heredoc body line")
      end
    end

    describe "lazy-load-aware skip via file_path:" do
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
        described_class.preloaded_features = Set.new(["/other/file.rb"])
        result = neutralizer.call(plugin_src, file_path: "/lazy/plugin.rb")

        expect(result).to eq(plugin_src)
        expect(result).to include("handle_type")
      end

      it "normalizes file paths so relative/absolute forms match the snapshot" do
        absolute = File.expand_path("lib/some_file.rb")
        described_class.preloaded_features = Set.new([absolute])
        result = neutralizer.call(plugin_src, file_path: "lib/some_file.rb")

        expect(result).not_to include("handle_type")
      end

      it "treats a non-expanded snapshot entry as a miss (paths are expanded)" do
        # The snapshot stores the literal relative string; preloaded? expands
        # the incoming path, so the relative entry does not match.
        described_class.preloaded_features = Set.new(["lib/some_file.rb"])
        result = neutralizer.call(plugin_src, file_path: "lib/some_file.rb")

        expect(result).to eq(plugin_src)
      end

      it "falls back to always-neutralize when file_path is not provided" do
        described_class.preloaded_features = Set.new([])
        result = neutralizer.call(plugin_src)

        expect(result).not_to include("handle_type")
      end
    end
  end
end
