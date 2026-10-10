# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::RescueClassWidening do
  def mutations_of(body)
    Tempfile.create(["rescue_class_widening", ".rb"]) do |file|
      File.write(file.path, "class Sample\n  def value(a)\n#{body}  end\nend\n")
      described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
    end
  end

  # The rescue lines of the method after each mutation.
  def rescue_lines(body)
    mutations_of(body).map { |m| m.mutated_source.lines.grep(/rescue/).map(&:strip) }
  end

  describe "#call" do
    it "widens a named class to StandardError and to Exception" do
      expect(rescue_lines("    a.call\n  rescue KeyError\n    1\n")).to eq([["rescue StandardError"], ["rescue Exception"]])
    end

    it "replaces a list of classes as a whole and keeps the variable" do
      expect(rescue_lines("    a.call\n  rescue KeyError, IndexError => e\n    e\n"))
        .to eq([["rescue StandardError => e"], ["rescue Exception => e"]])
    end

    it "replaces a namespaced class and a splatted list" do
      expect(rescue_lines("    a.call\n  rescue Net::ReadTimeout\n    1\n")).to eq([["rescue StandardError"], ["rescue Exception"]])
      expect(rescue_lines("    a.call\n  rescue *ERRORS\n    1\n")).to eq([["rescue StandardError"], ["rescue Exception"]])
    end

    it "widens StandardError to Exception only" do
      expect(rescue_lines("    a.call\n  rescue StandardError => e\n    e\n")).to eq([["rescue Exception => e"]])
      expect(rescue_lines("    a.call\n  rescue ::StandardError\n    1\n")).to eq([["rescue Exception"]])
      expect(rescue_lines("    a.call\n  rescue KeyError, StandardError\n    1\n")).to eq([["rescue Exception"]])
    end

    # A bare rescue is `rescue StandardError`.
    it "widens a bare rescue to Exception" do
      expect(rescue_lines("    a.call\n  rescue\n    1\n")).to eq([["rescue Exception"]])
      expect(rescue_lines("    a.call\n  rescue => e\n    e\n")).to eq([["rescue Exception => e"]])
    end

    it "leaves a rescue of Exception alone" do
      expect(mutations_of("    a.call\n  rescue Exception\n    1\n")).to be_empty
      expect(mutations_of("    a.call\n  rescue ::Exception => e\n    e\n")).to be_empty
      expect(mutations_of("    a.call\n  rescue KeyError, Exception\n    1\n")).to be_empty
    end

    it "widens each clause in turn" do
      body = "    a.call\n  rescue KeyError\n    1\n  rescue StandardError\n    2\n"

      expect(rescue_lines(body)).to eq(
        [["rescue StandardError", "rescue StandardError"], ["rescue Exception", "rescue StandardError"],
         ["rescue KeyError", "rescue Exception"]]
      )
    end

    it "widens the rescue of a begin block and of a do block" do
      expect(rescue_lines("    begin\n      a.call\n    rescue KeyError\n      1\n    end\n"))
        .to eq([["rescue StandardError"], ["rescue Exception"]])
      expect(rescue_lines("    a.each do |x|\n      x.call\n    rescue KeyError\n      1\n    end\n"))
        .to eq([["rescue StandardError"], ["rescue Exception"]])
    end

    it "leaves a rescue modifier alone" do
      expect(mutations_of("    a.call rescue 1\n")).to be_empty
    end

    it "reports the mutation on the line of the rescue" do
      expect(mutations_of("    a.call\n  rescue KeyError\n    1\n").map(&:line)).to eq([4, 4])
    end

    it "produces valid Ruby" do
      bodies = ["    a.call\n  rescue KeyError, IndexError => e\n    e\n", "    a.call\n  rescue\n    1\n",
                "    a.call\n  rescue => e\n    e\n", "    a.call\n  rescue *ERRORS then 1\n",
                "    begin\n      a.call\n    rescue KeyError then 1\n    else 2\n    ensure 3\n    end\n"]
      mutations = bodies.flat_map { |body| mutations_of(body) }

      expect(mutations).not_to be_empty
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      expect(mutations_of("    a.call\n  rescue\n    1\n").map(&:operator_name)).to eq(["rescue_class_widening"])
    end
  end
end
