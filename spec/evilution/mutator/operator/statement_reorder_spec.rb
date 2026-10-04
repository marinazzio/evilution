# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::StatementReorder do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["statement_reorder", ".rb"])
    tmpfile.write("class Checkout\n  def call(order, card, user)\n#{body}  end\nend\n")
    tmpfile.flush
    subject = Evilution::AST::Parser.new.call(tmpfile.path).first
    described_class.new.call(subject, filter: filter)
  ensure
    tmpfile.close
    tmpfile.unlink
  end

  # The method body of each mutant.
  def mutated_bodies(muts)
    muts.map { |m| m.mutated_source[/  def call\(.*?\)\n(.*)  end\nend\n\z/m, 1] }
  end

  describe "#call" do
    it "swaps two adjacent commands" do
      muts = mutations_for("    charge(card)\n    send_receipt(user)\n    order\n")

      expect(mutated_bodies(muts)).to eq(["    send_receipt(user)\n    charge(card)\n    order\n"])
    end

    it "swaps each adjacent pair of commands" do
      muts = mutations_for("    reserve(order)\n    charge(card)\n    send_receipt(user)\n    order\n")

      expect(mutated_bodies(muts)).to eq(
        [
          "    charge(card)\n    reserve(order)\n    send_receipt(user)\n    order\n",
          "    reserve(order)\n    send_receipt(user)\n    charge(card)\n    order\n"
        ]
      )
    end

    it "keeps what separates the statements in place" do
      muts = mutations_for("    charge(card); send_receipt(user)\n    order\n")

      expect(mutated_bodies(muts)).to eq(["    send_receipt(user); charge(card)\n    order\n"])
    end

    it "counts writes to instance variables, yield, super, appends and index writes as commands" do
      expect(mutated_bodies(mutations_for("    @cache.clear\n    @store.reload\n    order\n"))).to eq(
        ["    @store.reload\n    @cache.clear\n    order\n"]
      )
      expect(mutated_bodies(mutations_for("    order << card\n    yield(user)\n    order\n"))).to eq(
        ["    yield(user)\n    order << card\n    order\n"]
      )
      expect(mutated_bodies(mutations_for("    order[:card] = card\n    super(user)\n    order\n"))).to eq(
        ["    super(user)\n    order[:card] = card\n    order\n"]
      )
    end

    it "reorders the statements of a block" do
      muts = mutations_for("    order.each do |item|\n      reserve(item)\n      charge(item)\n      item\n    end\n")

      expect(mutated_bodies(muts)).to eq(
        ["    order.each do |item|\n      charge(item)\n      reserve(item)\n      item\n    end\n"]
      )
    end

    # The last statement gives the body its value; moving it mostly breaks
    # that value, which any test notices.
    it "does not move the last statement of a body" do
      expect(mutations_for("    charge(card)\n    send_receipt(user)\n")).to be_empty
    end

    # A pair that shares a variable fails at once when swapped: the reader
    # sees it unset or stale.
    it "skips a pair that shares a variable" do
      expect(mutations_for("    total = price(order)\n    charge(total)\n    order\n")).to be_empty
      expect(mutations_for("    @total = price(order)\n    charge(@total)\n    order\n")).to be_empty
      expect(mutations_for("    log(card)\n    card = refresh(card)\n    order\n")).to be_empty
    end

    # Commands can still share a variable: through a multiple assignment, a
    # global, or an assignment nested in an argument.
    it "skips commands that share a variable" do
      expect(mutations_for("    first, last = split(order)\n    log(first)\n    order\n")).to be_empty
      expect(mutations_for("    $count = tick(order)\n    log($count)\n    order\n")).to be_empty
      expect(mutations_for("    charge(total = price(order))\n    log(total)\n    order\n")).to be_empty
      expect(mutations_for("    log(card)\n    charge(card = refresh(user))\n    order\n")).to be_empty
      expect(mutations_for("    charge(total = 1)\n    log(total = 2)\n    order\n")).to be_empty
    end

    it "skips commands that share a class or global variable written in any form" do
      expect(mutations_for("    $count ||= tick(order)\n    log($count)\n    order\n")).to be_empty
      expect(mutations_for("    $count += tick(order)\n    log($count)\n    order\n")).to be_empty
      expect(mutations_for("    @@count &&= tick(order)\n    log(@@count)\n    order\n")).to be_empty
      expect(mutations_for("    $first, last = split(order)\n    log($first)\n    order\n")).to be_empty
      expect(mutations_for("    @@first, last = split(order)\n    log(@@first)\n    order\n")).to be_empty
    end

    it "swaps commands that only read the same variable" do
      muts = mutations_for("    charge(card)\n    log(card)\n    order\n")

      expect(mutated_bodies(muts)).to eq(["    log(card)\n    charge(card)\n    order\n"])
    end

    # A local assignment computes a value; moving it past a command that
    # does not use it rarely changes anything.
    it "skips a pair where one statement is a local assignment" do
      expect(mutations_for("    total = price(order)\n    log(card)\n    total\n")).to be_empty
    end

    # Storing a value in an instance variable is the same kind of statement as
    # a local assignment, typically one of several in a constructor.
    it "skips a pair where one statement assigns an instance variable" do
      expect(mutations_for("    @command = parse(order)\n    @options = load(card)\n    order\n")).to be_empty
      expect(mutations_for("    @total ||= price(order)\n    log(card)\n    order\n")).to be_empty
    end

    # Two different keys of one hash do not depend on each other.
    it "skips writes to different literal keys of the same receiver" do
      expect(mutations_for("    order[:card] = card\n    order[:user] = user\n    order\n")).to be_empty
      expect(mutations_for("    order[:card] = card if card\n    order[:user] = user if user\n    order\n")).to be_empty
    end

    it "swaps a command written as a condition with an empty body" do
      muts = mutations_for("    if charge(card) then end\n    log(card)\n    order\n")

      expect(mutated_bodies(muts)).to eq(["    log(card)\n    if charge(card) then end\n    order\n"])
    end

    it "skips literal-key writes under unless as well" do
      expect(mutations_for("    order[:card] = card unless card\n    order[:user] = user\n    order\n")).to be_empty
    end

    it "still swaps a literal-key write next to a computed key or a longer conditional" do
      expect(mutated_bodies(mutations_for("    order[:card] = 1\n    order[user] = 2\n    order\n"))).to eq(
        ["    order[user] = 2\n    order[:card] = 1\n    order\n"]
      )
      source = "    order[:card] = 1\n    if user\n      order[:user] = 2\n      log(user)\n    end\n    order\n"
      expect(mutations_for(source).length).to eq(1)
    end

    it "still swaps writes to the same key, computed keys or different receivers" do
      expect(mutated_bodies(mutations_for("    order[:card] = card\n    order[:card] = user\n    order\n"))).to eq(
        ["    order[:card] = user\n    order[:card] = card\n    order\n"]
      )
      expect(mutated_bodies(mutations_for("    order[card] = 1\n    order[user] = 2\n    order\n"))).to eq(
        ["    order[user] = 2\n    order[card] = 1\n    order\n"]
      )
      expect(mutated_bodies(mutations_for("    order[:a] = 1\n    card[:b] = 2\n    order\n"))).to eq(
        ["    card[:b] = 2\n    order[:a] = 1\n    order\n"]
      )
    end

    it "skips a pair without side effects" do
      expect(mutations_for("    @a = 1\n    @b = 2\n    order\n")).to be_empty
      expect(mutations_for("    order + card\n    user == card\n    order\n")).to be_empty
    end

    it "skips a command that contains control flow" do
      expect(mutations_for("    return charge(card) if user\n    log(card)\n    order\n")).to be_empty
      expect(mutations_for("    order.each { |item| break charge(item) }\n    log(card)\n    order\n")).to be_empty
    end

    it "swaps a fail sent to a receiver, which is not Kernel#fail" do
      muts = mutations_for("    order.fail(card)\n    log(card)\n    order\n")

      expect(mutated_bodies(muts)).to eq(["    log(card)\n    order.fail(card)\n    order\n"])
    end

    it "swaps commands with ordinary string arguments" do
      muts = mutations_for("    log(\"charged\")\n    charge(card)\n    order\n")

      expect(mutated_bodies(muts)).to eq(["    charge(card)\n    log(\"charged\")\n    order\n"])
    end

    it "skips a pair involving control flow" do
      expect(mutations_for("    return order if card\n    charge(card)\n    order\n")).to be_empty
      expect(mutations_for("    raise ArgumentError unless card\n    charge(card)\n    order\n")).to be_empty
      expect(mutations_for("    order.each do |item|\n      next unless item\n      charge(item)\n      item\n    end\n")).to be_empty
    end

    # A heredoc's body sits outside the statement's own source range, so the
    # swap cannot carry it along.
    it "skips a pair involving a heredoc" do
      expect(mutations_for("    log(<<~MSG)\n      charged\n    MSG\n    charge(card)\n    order\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for("    reserve(order)\n    charge(card); send_receipt(user)\n    order\n")

      expect(muts.length).to eq(2)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    charge(card)\n    send_receipt(user)\n    order\n")

      expect(muts.map(&:operator_name)).to eq(["statement_reorder"])
    end
  end
end
