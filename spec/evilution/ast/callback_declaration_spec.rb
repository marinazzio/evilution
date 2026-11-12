# frozen_string_literal: true

require "prism"
require "evilution/ast/callback_declaration"

RSpec.describe Evilution::AST::CallbackDeclaration do
  def statement(code)
    Prism.parse(code).value.statements.body.first
  end

  def callables(code)
    described_class.in_body(statement(code).body)
  end

  def summary(code)
    callables(code).map { |callable| [callable.label, callable.body.slice] }
  end

  describe ".in_body" do
    it "finds the literal conditions of callback and validation declarations" do
      code = <<~RUBY
        class Order
          validate :credit_limit, if: -> { paid? }
          validates :title, :body, presence: true, unless: lambda { draft? }
          validates_presence_of :total, if: proc { paid? }
          after_commit :notify, on: :create, if: ->(o) { o.notify? }
          before_action :authorize!, unless: -> { json? }
          around_save :audit, if: [-> { one }, :named, -> { two }]
        end
      RUBY

      expect(summary(code)).to eq(
        [
          ["validate(:credit_limit)", "-> { paid? }"],
          ["validates(:title)", "{ draft? }"],
          ["validates_presence_of(:total)", "{ paid? }"],
          ["after_commit(:notify)", "->(o) { o.notify? }"],
          ["before_action(:authorize!)", "-> { json? }"],
          ["around_save(:audit)", "-> { one }"],
          ["around_save(:audit)", "-> { two }"]
        ]
      )
    end

    it "finds callbacks given as a block or a lambda" do
      code = <<~RUBY
        class Order
          before_save { self.total = 0 }
          after_commit -> { notify }, on: :create
          validate do
            errors.add(:base, "no")
          end
          before_validation lambda { |order| order.trim }, proc { two }
        end
      RUBY

      expect(summary(code)).to eq(
        [
          ["before_save", "{ self.total = 0 }"],
          ["after_commit", "-> { notify }"],
          ["validate", "do\n    errors.add(:base, \"no\")\n  end"],
          ["before_validation", "{ |order| order.trim }"],
          ["before_validation", "{ two }"]
        ]
      )
    end

    it "lists a declaration's callback before its conditions and its block last" do
      code = "class Order\n  before_save -> { a }, if: -> { b } do\n    c\n  end\nend"

      expect(summary(code).map(&:last)).to eq(["-> { a }", "-> { b }", "do\n    c\n  end"])
    end

    it "gives each callable its body as what mutations go into" do
      code = "class Order\n  validate :a, if: -> { 1 }\nend"

      expect(callables(code).map { |callable| callable.node.slice }).to eq(["-> { 1 }"])
    end

    it "gives each callable its declaration" do
      code = "class Order\n  validate :a, if: -> { 1 }\n  validate :b, if: -> { 2 }\nend"

      expect(callables(code).map { |callable| callable.declaration.slice })
        .to eq(["validate :a, if: -> { 1 }", "validate :b, if: -> { 2 }"])
    end

    it "ignores symbol conditions and other keyword lambdas" do
      code = "class Order\n  validate :a, if: :paid?\n  validates :b, format: { with: -> { 1 } }, message: -> { 2 }\nend"

      expect(callables(code)).to eq([])
    end

    it "ignores calls that are not callback declarations" do
      code = <<~RUBY
        class Order
          scope :paid, -> { 1 }
          has_many :items, -> { 2 }
          validated :a, if: -> { 3 }
          before :a, if: -> { 4 }
          beforehand { 5 }
          afterwards_do { 6 }
        end
      RUBY

      expect(callables(code)).to eq([])
    end

    it "ignores declarations on a receiver or nested in another statement" do
      code = <<~RUBY
        class Order
          Other.validate :a, if: -> { 1 }
          self.before_save { 2 }
          if legacy?
            validate :b, if: -> { 3 }
          end
          def self.setup
            validate :c, if: -> { 4 }
          end
        end
      RUBY

      expect(callables(code)).to eq([])
    end

    it "ignores a declaration holding a heredoc" do
      code = "class Order\n  validate :a, if: -> { sql(<<~SQL) }\n    select 1\n  SQL\n  validate :b, if: -> { 1 }\nend"

      expect(summary(code)).to eq([["validate(:b)", "-> { 1 }"]])
    end

    it "does not take a shovel for a heredoc" do
      code = "class Order\n  before_save { log << 1 }\nend"

      expect(summary(code)).to eq([["before_save", "{ log << 1 }"]])
    end

    it "ignores a block handed over as an argument" do
      expect(callables("class Order\n  before_save(&handler)\nend")).to eq([])
    end

    it "reads a class body wrapped in a rescue, and returns nothing for an empty one" do
      wrapped = "class Order\n  validate :a, if: -> { 1 }\nrescue StandardError\n  nil\nend"

      expect(summary(wrapped)).to eq([["validate(:a)", "-> { 1 }"]])
      expect(callables("class Order\nend")).to eq([])
    end
  end

  describe ".options_in" do
    def options(code)
      described_class.options_in(statement(code).body)
    end

    it "finds the argument lists of the declarations given keyword options" do
      code = <<~RUBY
        class Vote
          validates :for_lift, inclusion: { in: [true] }, if: :lift_round?
          validate :within_window
          validates_presence_of :user, message: "is missing"
          before_save :normalize, unless: -> { draft? }
          after_commit on: :create do
            notify
          end
        end
      RUBY

      expect(options(code).map { |found| [found.label, found.arguments.slice] }).to eq(
        [
          ["validates(:for_lift)", ":for_lift, inclusion: { in: [true] }, if: :lift_round?"],
          ["validates_presence_of(:user)", ":user, message: \"is missing\""],
          ["before_save(:normalize)", ":normalize, unless: -> { draft? }"],
          ["after_commit", "on: :create"]
        ]
      )
    end

    it "gives each its declaration, and its argument list as what mutations go into" do
      code = "class Vote\n  validates :a, presence: true\nend"
      found = options(code).first

      expect([found.declaration.slice, found.node]).to eq(["validates :a, presence: true", found.arguments])
    end

    it "finds options written out beside a double splat" do
      code = "class Vote\n  validates :a, presence: true, **OPTIONS\nend"

      expect(options(code).map(&:label)).to eq(["validates(:a)"])
    end

    it "ignores options given as a hash literal or a double splat alone, and calls that are no declarations" do
      code = <<~RUBY
        class Vote
          validates :a, { presence: true }
          validates :b, **OPTIONS
          belongs_to :user, optional: true
          Other.validates :c, presence: true
          if legacy?
            validates :d, presence: true
          end
          validates :e, presence: true, message: <<~TEXT
            missing
          TEXT
        end
      RUBY

      expect(options(code)).to eq([])
    end

    it "returns nothing for an empty class body" do
      expect(options("class Vote\nend")).to eq([])
    end
  end

  describe ".match?" do
    it "accepts the declaration names" do
      %w[validate validates validates_each before_save after_commit around_action].each do |name|
        expect(described_class.match?(statement("#{name} :x"))).to be(true)
      end
    end

    it "rejects everything else" do
      ["scope :x, -> { 1 }", "x = 1", "Other.validate :x", "validator :x", "before :x", "aasm do\nend"].each do |code|
        expect(described_class.match?(statement(code))).to be(false)
      end
    end
  end
end
