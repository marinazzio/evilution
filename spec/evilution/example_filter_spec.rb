# frozen_string_literal: true

require "tempfile"
require "evilution/example_filter"
require "evilution/spec_ast_cache"

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
  end
end
