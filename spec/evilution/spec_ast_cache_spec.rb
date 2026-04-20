# frozen_string_literal: true

require "tempfile"
require "evilution/spec_ast_cache"

RSpec.describe Evilution::SpecAstCache do
  def write_spec(contents)
    file = Tempfile.new(["spec_ast_cache", ".rb"])
    file.write(contents)
    file.close
    file.path
  end

  let(:cache) { described_class.new }

  describe "#fetch" do
    it "returns Block entries for a describe + it spec" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          it "does a thing" do
            expect(true).to be true
          end
        end
      RUBY

      blocks = cache.fetch(path)

      kinds = blocks.map(&:kind)
      expect(kinds).to include(:describe, :it)
    end

    it "captures line and end_line for each block" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          it "one" do
            expect(true).to be true
          end
        end
      RUBY

      blocks = cache.fetch(path)
      it_block = blocks.find { |b| b.kind == :it }

      expect(it_block.line).to eq(2)
      expect(it_block.end_line).to eq(4)
    end

    it "lowercases body_text" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          it "does X" do
            CamelCase.call
          end
        end
      RUBY

      blocks = cache.fetch(path)
      it_block = blocks.find { |b| b.kind == :it }

      expect(it_block.body_text).to include("camelcase.call")
      expect(it_block.body_text).not_to include("CamelCase")
    end

    it "strips line comments from body_text (Prism-aware) but keeps string literals" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          it "thing" do
            foo_method # this should disappear
            description = "# not a comment"
          end
        end
      RUBY

      blocks = cache.fetch(path)
      it_block = blocks.find { |b| b.kind == :it }

      expect(it_block.body_text).to include("foo_method")
      expect(it_block.body_text).not_to include("this should disappear")
      expect(it_block.body_text).to include("# not a comment")
    end

    it "collects nested describe/context/it blocks" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          context "nested" do
            it "inner" do
              true
            end
          end
        end
      RUBY

      blocks = cache.fetch(path)
      kinds = blocks.map(&:kind)

      expect(kinds).to contain_exactly(:describe, :context, :it)
    end

    it "recognizes RSpec aliases (fcontext, xcontext, fit, xit, specify)" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          fcontext "a" do
            fit "b" do
              true
            end
          end
          xcontext "c" do
            xit "d" do
              true
            end
          end
          specify "e" do
            true
          end
        end
      RUBY

      kinds = cache.fetch(path).map(&:kind)

      expect(kinds).to include(:fcontext, :xcontext, :fit, :xit, :specify)
    end

    it "recognizes before and after hooks" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          before { setup_thing }
          after { teardown_thing }
          it "x" do
            true
          end
        end
      RUBY

      kinds = cache.fetch(path).map(&:kind)

      expect(kinds).to include(:before, :after)
    end

    it "caches results so a second fetch does not re-read the file" do
      path = write_spec(<<~RUBY)
        RSpec.describe Foo do
          it "x" do
            true
          end
        end
      RUBY

      first = cache.fetch(path)
      allow(File).to receive(:read).and_call_original
      second = cache.fetch(path)

      expect(File).not_to have_received(:read)
      expect(second).to eq(first)
    end

    it "raises Evilution::ParseError for malformed spec file" do
      path = write_spec("def broken(\n")

      expect { cache.fetch(path) }.to raise_error(Evilution::ParseError)
    end

    it "raises Evilution::ParseError when file does not exist" do
      expect { cache.fetch("/nonexistent/spec.rb") }.to raise_error(Evilution::ParseError)
    end
  end

  describe "LRU eviction" do
    it "evicts least-recently-used files when max_files is exceeded" do
      c = described_class.new(max_files: 2)
      paths = 3.times.map do
        write_spec(<<~RUBY)
          RSpec.describe Foo do
            it "x" do
              true
            end
          end
        RUBY
      end

      c.fetch(paths[0])
      c.fetch(paths[1])
      c.fetch(paths[2])

      expect(c.cached?(paths[0])).to be false
      expect(c.cached?(paths[1])).to be true
      expect(c.cached?(paths[2])).to be true
    end

    it "updates LRU order on access" do
      c = described_class.new(max_files: 2)
      paths = 3.times.map do
        write_spec(<<~RUBY)
          RSpec.describe Foo do
            it "x" do
              true
            end
          end
        RUBY
      end

      c.fetch(paths[0])
      c.fetch(paths[1])
      c.fetch(paths[0]) # bumps [0] to MRU
      c.fetch(paths[2]) # evicts [1]

      expect(c.cached?(paths[0])).to be true
      expect(c.cached?(paths[1])).to be false
      expect(c.cached?(paths[2])).to be true
    end

    it "evicts until total blocks fit under max_blocks" do
      many_blocks_spec = <<~RUBY
        RSpec.describe Foo do
          it("a") { true }
          it("b") { true }
          it("c") { true }
        end
      RUBY
      c = described_class.new(max_files: 100, max_blocks: 5)

      paths = 3.times.map { write_spec(many_blocks_spec) }
      # each spec yields 4 blocks (describe + 3 it). after 2 fetches → 8 blocks > 5 cap
      c.fetch(paths[0])
      c.fetch(paths[1])

      total_blocks = [paths[0], paths[1]].sum { |p| c.cached?(p) ? c.fetch(p).length : 0 }
      expect(total_blocks).to be <= 5
    end
  end
end
