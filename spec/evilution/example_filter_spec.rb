# frozen_string_literal: true

require "tempfile"
require "evilution/example_filter"
require "evilution/spec_ast_cache"
require "evilution/source_ast_cache"

RSpec.describe Evilution::ExampleFilter do
  before { @tempfiles = [] }

  after { @tempfiles.each(&:unlink) }

  def write_source(contents)
    file = Tempfile.new(["example_filter_source", ".rb"])
    file.write(contents)
    file.close
    @tempfiles << file
    file.path
  end

  def mutation(original_source:, line:, file_path: "lib/foo.rb")
    instance_double(
      Evilution::Mutation,
      original_source: original_source,
      line: line,
      file_path: file_path
    )
  end

  let(:cache) { Evilution::SpecAstCache.new }
  let(:filter) { described_class.new(cache: cache) }

  describe "token extraction" do
    it "extracts the method name when mutation.line is inside a def" do
      src = <<~RUBY
        class Foo
          def bar_method
            1 + 1
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "exercises bar_method" do
            Foo.new.bar_method
          end
          it "other thing" do
            true
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "extracts the class name when mutation.line is in class body outside a def" do
      src = <<~RUBY
        class PaymentGateway
          CONSTANT = 42
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe PaymentGateway do
          it "has the constant" do
            expect(PaymentGateway::CONSTANT).to eq(42)
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 2), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "extracts the module name when mutation.line is in module body outside a def" do
      src = <<~RUBY
        module Helpers
          CONSTANT = 42
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Helpers do
          it "has helpers" do
            Helpers::CONSTANT
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 2), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "uses unqualified class name (drops namespace)" do
      src = <<~RUBY
        module App
          class Checkout
            CONSTANT = 1
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe "Checkout" do
          it "x" do
            Checkout::CONSTANT
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "falls back when no enclosing def/class/module (top-level script)" do
      src = <<~RUBY
        require "something"
        puts "hello"
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe "top level" do
          it "x" do
            true
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 2), [spec_path])

      expect(locations).to eq([spec_path])
    end
  end

  describe "body-token scan" do
    it "respects word boundaries (does not match substring)" do
      src = <<~RUBY
        class Foo
          def overlay
            true
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "tests overlay_data" do
            overlay_data_helper
          end
          it "tests overlay" do
            Foo.new.overlay
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:5"])
    end

    it "emits smallest-enclosing-block when nested blocks both match" do
      src = <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          context "bar_method behavior" do
            it "returns one" do
              Foo.new.bar_method
            end
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:3"])
    end

    it "includes before-hook match at the enclosing describe level" do
      src = <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          before do
            @result = Foo.new.bar_method
          end
          it "x" do
            expect(@result).to eq(1)
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to include("#{spec_path}:2")
    end

    it "matches predicate method names ending in ?" do
      src = <<~RUBY
        class Foo
          def valid?
            true
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "is valid?" do
            Foo.new.valid?
          end
          it "other" do
            true
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "matches bang method names ending in !" do
      src = <<~RUBY
        class Foo
          def save!
            true
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "saves" do
            Foo.new.save!
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "spreads locations across multiple spec files" do
      src = <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
      spec1 = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "one" do
            Foo.new.bar_method
          end
        end
      RUBY
      spec2 = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "two" do
            Foo.new.bar_method
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec1, spec2])

      expect(locations).to contain_exactly("#{spec1}:2", "#{spec2}:2")
    end
  end

  describe "fallback behavior" do
    let(:src) do
      <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
    end
    let(:spec_path) do
      write_source(<<~RUBY)
        RSpec.describe Foo do
          it "does a different thing" do
            something_unrelated
          end
        end
      RUBY
    end

    it "returns spec_paths when fallback is :full_file and zero matches" do
      locations = described_class.new(cache: cache, fallback: :full_file)
                                 .call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq([spec_path])
    end

    it "returns nil when fallback is :unresolved and zero matches" do
      locations = described_class.new(cache: cache, fallback: :unresolved)
                                 .call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to be_nil
    end

    it "returns spec_paths when fallback is :full_file and token is nil (top-level)" do
      top_level_src = "puts 'hi'\nputs 'bye'\n"

      locations = described_class.new(cache: cache, fallback: :full_file)
                                 .call(mutation(original_source: top_level_src, line: 1), [spec_path])

      expect(locations).to eq([spec_path])
    end

    it "returns nil when fallback is :unresolved and token is nil" do
      top_level_src = "puts 'hi'\n"

      locations = described_class.new(cache: cache, fallback: :unresolved)
                                 .call(mutation(original_source: top_level_src, line: 1), [spec_path])

      expect(locations).to be_nil
    end
  end

  describe "source AST cache integration" do
    let(:src) do
      <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
    end
    let(:spec_path) do
      write_source(<<~RUBY)
        RSpec.describe Foo do
          it "exercises bar_method" do
            Foo.new.bar_method
          end
        end
      RUBY
    end

    it "parses mutation.original_source once when reused with a source_cache" do
      source_cache = Evilution::SourceAstCache.new
      filter_with_cache = described_class.new(cache: cache, source_cache: source_cache)

      mutation_parse_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        mutation_parse_count += 1 if arg == src
        original.call(arg)
      end

      filter_with_cache.call(mutation(original_source: src, line: 3), [spec_path])
      filter_with_cache.call(mutation(original_source: src, line: 3), [spec_path])

      expect(mutation_parse_count).to eq(1)
    end

    it "parses mutation.original_source per call when no source_cache is injected" do
      mutation_parse_count = 0
      original = Prism.method(:parse)
      allow(Prism).to receive(:parse) do |arg|
        mutation_parse_count += 1 if arg == src
        original.call(arg)
      end

      filter.call(mutation(original_source: src, line: 3), [spec_path])
      filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(mutation_parse_count).to eq(2)
    end
  end

  describe "location formatting" do
    it "dedups identical locations across matching siblings and sorts output" do
      src = <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "a" do
            Foo.new.bar_method
          end
          it "b" do
            Foo.new.bar_method
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2", "#{spec_path}:5"])
    end

    it "sorts locations even when spec_paths are passed in reverse order" do
      src = <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
      spec_a, spec_b = [
        write_source("RSpec.describe Foo do\n  it \"a\" do\n    Foo.new.bar_method\n  end\nend\n"),
        write_source("RSpec.describe Foo do\n  it \"b\" do\n    Foo.new.bar_method\n  end\nend\n")
      ].sort

      locations = filter.call(mutation(original_source: src, line: 3), [spec_b, spec_a])

      expect(locations).to eq(["#{spec_a}:2", "#{spec_b}:2"])
    end

    it "dedups a location when the same spec path is listed twice" do
      src = <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "a" do
            Foo.new.bar_method
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path, spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end
  end

  describe "empty or missing spec paths" do
    let(:src) do
      <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
    end

    it "returns the fallback without scanning when spec_paths is nil" do
      filter_full = described_class.new(cache: cache, fallback: :full_file)

      locations = filter_full.call(mutation(original_source: src, line: 3), nil)

      expect(locations).to be_nil
    end

    it "returns the fallback without scanning when spec_paths is empty" do
      filter_unresolved = described_class.new(cache: cache, fallback: :unresolved)

      locations = filter_unresolved.call(mutation(original_source: src, line: 3), [])

      expect(locations).to be_nil
    end

    it "returns the full-file fallback value (the empty paths) for empty spec_paths" do
      filter_full = described_class.new(cache: cache, fallback: :full_file)

      locations = filter_full.call(mutation(original_source: src, line: 3), [])

      expect(locations).to eq([])
    end
  end

  describe "invalid mutation source" do
    let(:spec_path) do
      write_source(<<~RUBY)
        RSpec.describe Foo do
          it "covers bar_method" do
            Foo.new.bar_method
          end
        end
      RUBY
    end

    it "falls back when mutation.original_source fails to parse" do
      unparseable = "class Foo\n  def bar_method\n    1\n  end\nend\n)"

      filter_unresolved = described_class.new(cache: cache, fallback: :unresolved)
      locations = filter_unresolved.call(mutation(original_source: unparseable, line: 3), [spec_path])

      expect(locations).to be_nil
    end
  end

  describe "argument validation" do
    it "raises ArgumentError for an unrecognized fallback symbol" do
      expect { described_class.new(cache: cache, fallback: :bogus) }
        .to raise_error(ArgumentError, "invalid fallback: :bogus")
    end

    it "names the offending fallback value in the error message" do
      expect { described_class.new(cache: cache, fallback: "full_file") }
        .to raise_error(ArgumentError, /invalid fallback: "full_file"/)
    end
  end

  describe "enclosing-node traversal" do
    it "captures the method name, not the enclosing class name, for a def target" do
      src = <<~RUBY
        class Foo
          def bar_method
            1
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "exercises bar_method" do
            Foo.new.bar_method
          end
          it "mentions Foo only" do
            Foo
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "descends into a method nested in a class to capture the method name" do
      src = <<~RUBY
        class Outer
          def inner_method
            42
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Outer do
          it "calls inner_method" do
            Outer.new.inner_method
          end
          it "mentions Outer only" do
            Outer
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "descends into a method nested in a module to capture the method name" do
      src = <<~RUBY
        module Outer
          def inner_method
            42
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Outer do
          it "calls inner_method" do
            Outer.inner_method
          end
          it "mentions Outer only" do
            Outer
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "ignores a def whose body does not contain the target line" do
      src = <<~RUBY
        class Foo
          def first_method
            1
          end

          def second_method
            2
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "covers first_method" do
            Foo.new.first_method
          end
          it "covers second_method" do
            Foo.new.second_method
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 7), [spec_path])

      expect(locations).to eq(["#{spec_path}:5"])
    end

    it "stops at the first matching def and ignores later defs" do
      src = <<~RUBY
        class Foo
          def alpha_method
            1
          end

          def beta_method
            2
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "covers alpha_method" do
            Foo.new.alpha_method
          end
          it "covers beta_method" do
            Foo.new.beta_method
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 3), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "captures the inner class name when target is in a sibling-free nested class" do
      src = <<~RUBY
        module Outer
          class FirstClass
            CONST_A = 1
          end

          class SecondClass
            CONST_B = 2
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Outer do
          it "covers FirstClass" do
            Outer::FirstClass::CONST_A
          end
          it "covers SecondClass" do
            Outer::SecondClass::CONST_B
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 7), [spec_path])

      expect(locations).to eq(["#{spec_path}:5"])
    end

    it "stops descending once an enclosing method is captured" do
      src = <<~RUBY
        class Foo
          def builder_method
            helper = Class.new do
              def deep_helper
                1
              end
            end
            helper
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "covers builder_method" do
            Foo.new.builder_method
          end
          it "covers deep_helper" do
            deep_helper_thing
          end
        end
      RUBY

      locations = filter.call(mutation(original_source: src, line: 5), [spec_path])

      expect(locations).to eq(["#{spec_path}:2"])
    end

    it "does not resolve a token when the target line is outside every block" do
      src = <<~RUBY
        TOP_CONSTANT = 1
        class Foo
          def bar_method
            2
          end
        end
      RUBY
      spec_path = write_source(<<~RUBY)
        RSpec.describe Foo do
          it "covers bar_method" do
            Foo.new.bar_method
          end
        end
      RUBY

      filter_unresolved = described_class.new(cache: cache, fallback: :unresolved)
      locations = filter_unresolved.call(mutation(original_source: src, line: 1), [spec_path])

      expect(locations).to be_nil
    end
  end
end
