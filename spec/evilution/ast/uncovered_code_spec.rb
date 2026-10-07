# frozen_string_literal: true

require "tempfile"
require "evilution/ast/parser"
require "evilution/ast/uncovered_code"

RSpec.describe Evilution::AST::UncoveredCode do
  def uncovered(source, lines: nil, mutated_lines: [])
    tmpfile = Tempfile.new(["uncovered", ".rb"])
    tmpfile.write(source)
    tmpfile.close
    subjects = Evilution::AST::Parser.new.call(tmpfile.path)

    described_class.call(tmpfile.path, subjects, lines: lines, mutated_lines: mutated_lines)
  ensure
    tmpfile.unlink if tmpfile
  end

  let(:model) do
    <<~RUBY
      class Order
        STATUSES = %w[draft paid].freeze

        has_many :items, ->(order) do
          where(order: order).where(visible: true)
        end

        def total
          items.sum(&:price)
        end
      end
    RUBY
  end

  it "returns the lines of class-body code outside every method" do
    expect(uncovered(model)).to eq([2..2, 4..6])
  end

  it "keeps only the lines inside the given range" do
    expect(uncovered(model, lines: 5..10)).to eq([5..6])
  end

  it "returns nothing for a range that holds only methods" do
    expect(uncovered(model, lines: 8..10)).to eq([])
  end

  it "returns top-level code outside any class" do
    source = <<~RUBY
      LIMIT = 10
      puts LIMIT
    RUBY

    expect(uncovered(source)).to eq([1..2])
  end

  it "looks into nested modules and class << self bodies" do
    source = <<~RUBY
      module Billing
        class Invoice
          class << self
            attr_reader :count
          end
        end
      end
    RUBY

    expect(uncovered(source)).to eq([4..4])
  end

  it "ignores visibility keywords without arguments" do
    source = <<~RUBY
      class Order
        private

        def total
          1
        end
      end
    RUBY

    expect(uncovered(source)).to eq([])
  end

  it "reports a visibility call that names methods" do
    source = <<~RUBY
      class Order
        def total
          1
        end
        private :total
      end
    RUBY

    expect(uncovered(source)).to eq([5..5])
  end

  it "treats value-object definitions as covered by their subject" do
    source = <<~RUBY
      Point = Data.define(:x, :y) do
        def norm
          x + y
        end
      end
    RUBY

    expect(uncovered(source)).to eq([])
  end

  it "looks into a class body that has a rescue clause" do
    source = <<~RUBY
      class Loader
        VERSION = 1
      rescue LoadError
        nil
      end
    RUBY

    expect(uncovered(source)).to eq([2..2])
  end

  it "keeps every uncovered line when the range spans the whole file" do
    expect(uncovered(model, lines: 1..20)).to eq([2..2, 4..6])
  end

  it "reports a line holding several statements once" do
    source = <<~RUBY
      class Limits
        MIN = 1; MAX = 2
      end
    RUBY

    expect(uncovered(source)).to eq([2..2])
  end

  it "reports a macro called without arguments" do
    source = <<~RUBY
      class Item
        acts_as_list
      end
    RUBY

    expect(uncovered(source)).to eq([2..2])
  end

  it "reports a visibility-named method called on a receiver" do
    source = <<~RUBY
      class Item
        record.public
      end
    RUBY

    expect(uncovered(source)).to eq([2..2])
  end

  it "returns nothing for empty bodies" do
    source = <<~RUBY
      class Empty
      end

      class Guarded
      rescue LoadError
        nil
      end
    RUBY

    expect(uncovered(source)).to eq([])
  end

  it "treats scope declarations as covered by their subject" do
    source = <<~RUBY
      class Order
        scope :paid,
              -> { where(paid: true) }
      end
    RUBY

    expect(uncovered(source)).to eq([])
  end

  it "reports the statements of a concern's included block, not the block around them" do
    source = <<~RUBY
      module Publishable
        included do
          validates :title, presence: true
          scope :published, -> { where(published: true) }
        end
      end
    RUBY

    expect(uncovered(source)).to eq([3..3])
  end

  it "treats callback declarations with a literal condition or body as covered by their subject" do
    source = <<~RUBY
      class Order
        after_commit :notify, if: ->(order) do
          order.paid? && order.total.positive?
        end
        before_save { self.total = 0 }
        before_save :named
      end
    RUBY

    expect(uncovered(source)).to eq([6..6])
  end

  it "returns nothing for an empty file" do
    expect(uncovered("")).to eq([])
  end

  it "leaves out require and require_relative statements" do
    source = <<~RUBY
      require "set"
      require_relative "base"

      LIMIT = 10

      class Order
        require "json"
        STATUSES = %w[draft paid].freeze
      end
    RUBY

    expect(uncovered(source)).to eq([4..4, 8..8])
  end

  it "reports a require called on a receiver" do
    source = <<~RUBY
      Kernel.require "set"
    RUBY

    expect(uncovered(source)).to eq([1..1])
  end

  it "leaves out a statement that a mutation targets" do
    source = <<~RUBY
      class Order
        LIMIT = 10
        alias_method :sum, :total

        def total
          1
        end
      end
    RUBY

    expect(uncovered(source, mutated_lines: [3])).to eq([2..2])
  end

  it "leaves out every line of a multi-line statement that a mutation targets" do
    source = <<~RUBY
      class Order
        alias_method(
          :sum,
          :total
        )
        LIMIT = 10
      end
    RUBY

    expect(uncovered(source, mutated_lines: [2])).to eq([6..6])
  end

  it "keeps a statement sharing no line with a mutation" do
    expect(uncovered(model, mutated_lines: [3, 9])).to eq([2..2, 4..6])
  end
end
