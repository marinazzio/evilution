# frozen_string_literal: true

require "prism"
require "evilution/ast/aasm_declaration"

RSpec.describe Evilution::AST::AasmDeclaration do
  def class_body(code)
    Prism.parse(code).value.statements.body.first.body
  end

  def callables(code)
    described_class.in_body(class_body(code))
  end

  def summary(code)
    callables(code).map { |callable| [callable.method_name, callable.body.slice] }
  end

  let(:order) do
    <<~RUBY
      class Order
        include AASM

        aasm column: :status do
          after_all_transitions -> { log! }
          state :paid, initial: true, before_exit: -> { leaving }
          state :shipped, :delivered, enter: [-> { one }, :named, lambda { two }]
          event :ship, guard: -> { address? }, after: :notify do
            before { prepare }
            transitions from: :paid, to: :shipped, guard: -> { ready? }, after: proc { done }
            error do |e|
              report(e)
            end
          end
          event :cancel do
            transitions from: :paid, to: :paid
          end
        end
      end
    RUBY
  end

  describe ".in_body" do
    it "finds the literal callables of events, their transitions and callback blocks, and states" do
      expect(summary(order)).to eq(
        [
          ["paid?", "-> { leaving }"],
          ["shipped?", "-> { one }"],
          ["shipped?", "{ two }"],
          ["ship", "-> { address? }"],
          ["ship", "{ prepare }"],
          ["ship", "-> { ready? }"],
          ["ship", "{ done }"],
          ["ship", "do |e|\n        report(e)\n      end"]
        ]
      )
    end

    it "gives each callable the declaration it belongs to" do
      declarations = callables(order).map { |callable| callable.declaration.slice.lines.first.strip }

      expect(declarations.uniq).to eq(
        [
          "state :paid, initial: true, before_exit: -> { leaving }",
          "state :shipped, :delivered, enter: [-> { one }, :named, lambda { two }]",
          "event :ship, guard: -> { address? }, after: :notify do"
        ]
      )
    end

    it "leaves the machine's own callbacks alone" do
      expect(summary(order).map(&:last)).not_to include("-> { log! }")
    end

    it "finds a named machine and a brace block" do
      code = "class Order\n  aasm(:shipping) { event(:ship, guard: -> { ok? }) { transitions from: :a, to: :b } }\nend"

      expect(summary(code)).to eq([["ship", "-> { ok? }"]])
    end

    it "finds every machine of the class" do
      code = <<~RUBY
        class Order
          aasm(:payment) do
            event :pay, guard: -> { a } do
            end
          end
          aasm(:shipping) do
            event :ship, guard: -> { b } do
            end
          end
        end
      RUBY

      expect(summary(code)).to eq([["pay", "-> { a }"], ["ship", "-> { b }"]])
    end

    it "reads a class body wrapped in a rescue" do
      code = "class Order\n  aasm do\n    event :ship, guard: -> { ok? }\n  end\nrescue StandardError\n  nil\nend"

      expect(summary(code)).to eq([["ship", "-> { ok? }"]])
    end

    it "ignores a machine called on a receiver or without a block" do
      ["class Order\n  Other.aasm do\n    event :ship, guard: -> { 1 }\n  end\nend",
       "class Order\n  aasm column: :status\nend",
       "class Order\n  aasm(&machine)\nend"].each do |code|
        expect(callables(code)).to eq([])
      end
    end

    it "ignores a machine that is not a direct statement of the class body" do
      code = "class Order\n  if rails?\n    aasm do\n      event :ship, guard: -> { 1 }\n    end\n  end\nend"

      expect(callables(code)).to eq([])
    end

    it "ignores events and states that are not named by a symbol or have a receiver" do
      code = <<~RUBY
        class Order
          aasm do
            event name, guard: -> { 1 }
            state "paid", enter: -> { 2 }
            machine.event :ship, guard: -> { 3 }
            other :ship, guard: -> { 4 }
          end
        end
      RUBY

      expect(callables(code)).to eq([])
    end

    it "ignores callback-named calls that carry arguments, a receiver or no block" do
      code = <<~RUBY
        class Order
          aasm do
            event :ship do
              before :prepare
              after(:x) { one }
              self.error { two }
              helper { three }
              nested do
                before { four }
              end
            end
          end
        end
      RUBY

      expect(callables(code)).to eq([])
    end

    it "ignores a block-taking call that is not an aasm machine" do
      code = "class Order\n  configure do\n    event :ship, guard: -> { 1 }\n  end\nend"

      expect(callables(code)).to eq([])
    end

    it "does not read a state's block as an event's" do
      code = "class Order\n  aasm do\n    state :paid do\n      before { 1 }\n      transitions guard: -> { 2 }\n    end\n  end\nend"

      expect(callables(code)).to eq([])
    end

    it "ignores a callback handed over as a block argument" do
      code = "class Order\n  aasm do\n    event :ship do\n      before(&handler)\n    end\n  end\nend"

      expect(callables(code)).to eq([])
    end

    it "skips splatted options next to a literal guard" do
      code = "class Order\n  aasm do\n    event :ship, **options, guard: -> { 1 }\n  end\nend"

      expect(summary(code)).to eq([["ship", "-> { 1 }"]])
    end

    it "steps over statements that are not calls, and calls without arguments" do
      code = <<~RUBY
        class Order
          aasm do
            limit = 3
            event
            state
            event :ship do
              tries = limit
              transitions
              transitions from: :a, to: :b, guard: -> { tries }
            end
          end
        end
      RUBY

      expect(summary(code)).to eq([["ship", "-> { tries }"]])
    end

    it "ignores callables that are not keyword values" do
      code = "class Order\n  aasm do\n    event :ship, -> { 1 } do\n      transitions(-> { 2 })\n    end\n  end\nend"

      expect(callables(code)).to eq([])
    end

    it "returns nothing for an empty body, an empty machine or an empty event" do
      ["class Order\nend", "class Order\n  aasm do\n  end\nend", "class Order\n  aasm do\n    event :ship do\n    end\n  end\nend"]
        .each { |code| expect(callables(code)).to eq([]) }
    end
  end

  describe ".machine_block" do
    def statement(code)
      Prism.parse(code).value.statements.body.first
    end

    it "returns the block of an aasm call" do
      expect(described_class.machine_block(statement("aasm do\nend"))).to be_a(Prism::BlockNode)
    end

    it "returns nil for other nodes" do
      ["aasm", "scope :x, -> { 1 }", "Other.aasm { 1 }", "x = 1", "aasm(&blk)", "configure do\nend"].each do |code|
        expect(described_class.machine_block(statement(code))).to be_nil
      end
    end
  end

  describe ".token_at" do
    let(:machine) { class_body(order).body[1] }

    it "names the event a line belongs to" do
      expect(described_class.token_at(machine, 10)).to eq("ship")
    end

    it "names the first state of a state declaration" do
      expect(described_class.token_at(machine, 7)).to eq("shipped")
    end

    it "returns nil for a line outside every event and state" do
      expect(described_class.token_at(machine, 5)).to be_nil
    end

    it "returns nil for a node that is not a machine" do
      expect(described_class.token_at(class_body(order).body[0], 2)).to be_nil
    end
  end
end
