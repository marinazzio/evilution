# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::ExceptionSwallow do
  def mutations_for(body, filter: nil)
    tmpfile = Tempfile.new(["exception_swallow", ".rb"])
    tmpfile.write("class Svc\n  def call(record, h, v)\n#{body}  end\nend\n")
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
    it "swallows the error of a bang method" do
      muts = mutations_for("    record.save!\n    notify(record)\n")

      expect(mutated_bodies(muts)).to eq(["    record.save! rescue nil\n    notify(record)\n"])
    end

    it "swallows the error of fetch" do
      muts = mutations_for("    h.fetch(:body)\n")

      expect(mutated_bodies(muts)).to eq(["    h.fetch(:body) rescue nil\n"])
    end

    it "swallows the error of a conversion function" do
      %w[Integer Float Rational].each do |function|
        expect(mutated_bodies(mutations_for("    #{function}(v)\n"))).to eq(["    #{function}(v) rescue nil\n"])
      end
    end

    it "swallows the error of a raising call assigned to a variable" do
      expect(mutated_bodies(mutations_for("    data = h.fetch(:body)\n    data\n"))).to eq(
        ["    data = h.fetch(:body) rescue nil\n    data\n"]
      )
      expect(mutated_bodies(mutations_for("    @data = Integer(v)\n"))).to eq(["    @data = Integer(v) rescue nil\n"])
    end

    it "swallows the error of a call guarded by a modifier condition" do
      muts = mutations_for("    record.save! if v\n")

      expect(mutated_bodies(muts)).to eq(["    record.save! rescue nil if v\n"])
    end

    it "swallows the error of a call with a do block" do
      muts = mutations_for("    record.update!(v) do |r|\n      r\n    end\n")

      expect(mutated_bodies(muts)).to eq(["    record.update!(v) do |r|\n      r\n    end rescue nil\n"])
    end

    it "swallows the error of a statement inside a block" do
      muts = mutations_for("    v.each { |item| item.fetch(:a) }\n")

      expect(mutated_bodies(muts)).to eq(["    v.each { |item| item.fetch(:a) rescue nil }\n"])
    end

    it "swallows each raising statement separately" do
      muts = mutations_for("    record.save!\n    h.fetch(:a)\n")

      expect(mutated_bodies(muts)).to eq(
        ["    record.save! rescue nil\n    h.fetch(:a)\n", "    record.save!\n    h.fetch(:a) rescue nil\n"]
      )
    end

    # Ruby's own in-place bangs mark a method that changes its receiver, not
    # one that raises; exit! ends the process without raising.
    it "leaves in-place bangs from Ruby core and exit! alone" do
      %w[uniq! sort! sort_by! select! reject! map! compact! flatten! slice! merge! gsub! strip!].each do |bang|
        expect(mutations_for("    v.#{bang}\n")).to be_empty
      end
      expect(mutations_for("    exit!(1)\n")).to be_empty
    end

    it "still swallows a project bang that shares no name with Ruby core" do
      expect(mutated_bodies(mutations_for("    record.validate!\n"))).to eq(["    record.validate! rescue nil\n"])
    end

    # With a default value or a block, fetch returns that instead of raising.
    it "leaves fetch with a default or a block alone" do
      expect(mutations_for("    h.fetch(:a, nil)\n")).to be_empty
      expect(mutations_for("    h.fetch(:a) { v }\n")).to be_empty
      expect(mutations_for("    h.fetch(:a, &v)\n")).to be_empty
    end

    # A receiverless fetch is a method of the class itself, and a conversion
    # function sent to a receiver is not Kernel's.
    it "leaves a receiverless fetch and a conversion function with a receiver alone" do
      expect(mutations_for("    fetch(:a)\n")).to be_empty
      expect(mutations_for("    v.Integer(h)\n")).to be_empty
    end

    it "swallows fetch called without arguments" do
      expect(mutated_bodies(mutations_for("    h.fetch\n"))).to eq(["    h.fetch rescue nil\n"])
    end

    it "leaves calls that do not raise by convention alone" do
      expect(mutations_for("    record.save\n    notify(record)\n    h[:a]\n")).to be_empty
    end

    it "leaves negation and inequality alone" do
      expect(mutations_for("    !record\n    record != v\n")).to be_empty
    end

    # The statement is already guarded; adding another rescue changes nothing
    # the original handler does not already decide.
    it "leaves statements that are already rescued alone" do
      expect(mutations_for("    record.save! rescue false\n")).to be_empty
      expect(mutations_for("    begin\n      record.save!\n    rescue StandardError\n      nil\n    end\n")).to be_empty
    end

    it "still swallows inside a begin block that has no rescue clause" do
      muts = mutations_for("    begin\n      record.save!\n    ensure\n      v.close\n    end\n")

      expect(mutated_bodies(muts)).to eq(["    begin\n      record.save! rescue nil\n    ensure\n      v.close\n    end\n"])
    end

    it "swallows statements after a rescued block again" do
      muts = mutations_for("    begin\n      record.save!\n    rescue StandardError\n      nil\n    end\n    h.fetch(:a)\n")

      expect(mutated_bodies(muts)).to eq(
        ["    begin\n      record.save!\n    rescue StandardError\n      nil\n    end\n    h.fetch(:a) rescue nil\n"]
      )
    end

    it "swallows nested statements after a rescued block" do
      muts = mutations_for("    begin\n      record.save!\n    rescue StandardError\n      nil\n    end\n    v.each { h.fetch(:a) }\n")

      expect(mutated_bodies(muts)).to eq(
        ["    begin\n      record.save!\n    rescue StandardError\n      nil\n    end\n    v.each { h.fetch(:a) rescue nil }\n"]
      )
    end

    it "leaves statements nested inside a rescued block alone" do
      muts = mutations_for("    begin\n      v.each { h.fetch(:a) }\n    rescue StandardError\n      nil\n    end\n")

      expect(muts).to be_empty
    end

    it "leaves the body of a method with its own rescue clause alone" do
      tmpfile = Tempfile.new(["exception_swallow", ".rb"])
      tmpfile.write("class Svc\n  def call(record)\n    record.save!\n  rescue StandardError\n    nil\n  end\nend\n")
      tmpfile.flush
      subject = Evilution::AST::Parser.new.call(tmpfile.path).first

      expect(described_class.new.call(subject)).to be_empty
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    # `raise X rescue nil` behaves as deleting the statement, which
    # StatementDeletion already does.
    it "leaves raise alone" do
      expect(mutations_for("    raise ArgumentError\n")).to be_empty
    end

    it "leaves a raising call used as an argument or receiver alone" do
      expect(mutations_for("    notify(record.save!)\n")).to be_empty
      expect(mutations_for("    h.fetch(:a).strip\n")).to be_empty
    end

    it "produces parseable mutations" do
      muts = mutations_for(
        "    record.save! if v\n    data = h.fetch(:a)\n    record.update!(v) do |r|\n      r\n    end\n    data\n"
      )

      expect(muts.length).to eq(3)
      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    it "sets the operator name" do
      muts = mutations_for("    record.save!\n")

      expect(muts.map(&:operator_name)).to eq(["exception_swallow"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=fetch}"])

      muts = mutations_for("    h.fetch(:a)\n", filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
