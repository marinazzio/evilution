# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::BlockBodyPromotion do
  let(:fixture_path) do
    File.expand_path("../../../support/fixtures/block_body_promotion.rb", __dir__)
  end
  let(:source) { File.read(fixture_path) }
  let(:tree) { Prism.parse(source).value }

  def subjects_from_fixture
    finder = Evilution::AST::SubjectFinder.new(source, fixture_path)
    finder.visit(tree)
    finder.subjects
  end

  def mutations_for(method_name)
    subject = subjects_from_fixture.find { |s| s.name.end_with?("##{method_name}") }
    described_class.new.call(subject)
  end

  def mutations_from_source(inline_source)
    Tempfile.create(["block_body_promotion", ".rb"]) do |tmpfile|
      tmpfile.write(inline_source)
      tmpfile.flush
      Evilution::AST::Parser.new.call(tmpfile.path).flat_map { |s| described_class.new.call(s) }
    end
  end

  def mutated_lines(muts)
    muts.map { |m| m.mutated_slice.strip }
  end

  describe "#call" do
    it "replaces the call with a single-statement body" do
      expect(mutated_lines(mutations_for("single_statement"))).to eq(["account.save!"])
    end

    it "groups a multi-statement body in parentheses" do
      muts = mutations_for("multi_statement")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        a_string_including("    (record.lock!\n      record.update!(state: :done)\n      record)\n")
      )
    end

    it "keeps the grouped body's value in value position" do
      muts = mutations_for("value_position")

      expect(muts.map(&:mutated_source)).to contain_exactly(
        a_string_including("result = (record.touch\n      record.reload)\n")
      )
    end

    it "unwraps an iterator block without parameters" do
      muts = mutations_from_source("def t\n  3.times { retry_call }\nend\n")

      expect(mutated_lines(muts)).to eq(["retry_call"])
    end

    it "unwraps nested blocks independently" do
      muts = mutations_from_source("def t\n  outer { inner { work } }\nend\n")

      expect(mutated_lines(muts)).to contain_exactly("inner { work }", "outer { work }")
    end

    it "produces a parseable mutant from each promotion" do
      muts = subjects_from_fixture.flat_map { |s| described_class.new.call(s) }

      expect(muts.map(&:parse_status).uniq).to eq([:ok])
    end

    # Unwrapping a lock or a thread is how this operator probes concurrency
    # claims: the body runs unguarded, or inline on the caller's thread. A
    # separate operator for the same edit was proposed and dropped in favour
    # of these cases.
    it "unwraps a Mutex#synchronize block" do
      muts = mutations_from_source("def t\n  @mutex.synchronize { @count += 1 }\nend\n")

      expect(mutated_lines(muts)).to eq(["@count += 1"])
    end

    it "unwraps a multi-line synchronize block, grouping its statements" do
      muts = mutations_from_source("def t\n  @mutex.synchronize do\n    @count += 1\n    log(@count)\n  end\nend\n")

      expect(muts.map(&:mutated_source)).to eq(["def t\n  (@count += 1\n    log(@count))\nend\n"])
    end

    it "unwraps a Monitor#synchronize block" do
      muts = mutations_from_source("def t\n  @monitor.synchronize { tick }\nend\n")

      expect(mutated_lines(muts)).to eq(["tick"])
    end

    it "runs the body of a Thread.new block inline" do
      muts = mutations_from_source("def t\n  Thread.new { work }\nend\n")

      expect(mutated_lines(muts)).to eq(["work"])
    end

    # Inlining would need the thread's arguments bound to the block
    # parameters; like any block with parameters, it is left alone.
    it "leaves a Thread.new block with parameters alone" do
      expect(mutations_from_source("def t(job)\n  Thread.new(job) { |j| j.run }\nend\n")).to be_empty
    end

    it "unwraps a block with explicitly empty pipes" do
      muts = mutations_from_source("def t\n  wrap { || work }\nend\n")

      expect(mutated_lines(muts)).to eq(["work"])
    end

    it "skips a block declaring block-local variables" do
      expect(mutations_from_source("def t\n  wrap { |;tmp| tmp = work }\nend\n")).to be_empty
    end

    it "skips a block with parameters" do
      expect(mutations_for("with_parameters")).to be_empty
    end

    it "skips a numbered-parameter block" do
      expect(mutations_for("numbered_parameter")).to be_empty
    end

    it "skips an it-parameter block" do
      expect(mutations_from_source("def t(items)\n  items.each { process(it) }\nend\n")).to be_empty
    end

    it "skips a body using break, which is invalid outside a block" do
      expect(mutations_for("with_break")).to be_empty
    end

    it "skips a body using next" do
      expect(mutations_from_source("def t\n  wrap { next 1 }\nend\n")).to be_empty
    end

    it "skips a body with a rescue clause" do
      expect(mutations_for("with_rescue")).to be_empty
    end

    it "skips an empty block" do
      expect(mutations_for("empty_block")).to be_empty
    end

    it "skips a block-pass" do
      expect(mutations_for("block_pass")).to be_empty
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_for("single_statement").map(&:line)).to eq([3])
    end

    it "names the operator" do
      expect(mutations_for("single_statement").map(&:operator_name).uniq).to eq(["block_body_promotion"])
    end

    it "honours the equivalent-mutant filter" do
      filter = Evilution::AST::Pattern::Filter.new(["call{name=transaction}"])
      subject = subjects_from_fixture.find { |s| s.name.end_with?("#single_statement") }

      muts = described_class.new.call(subject, filter: filter)

      expect(muts).to be_empty
      expect(filter.skipped_count).to eq(1)
    end
  end
end
