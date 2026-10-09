# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::SafeNavigationInsertion do
  def mutations_of(body)
    Tempfile.create(["safe_navigation_insertion", ".rb"]) do |file|
      File.write(file.path, "class Sample\n  def value(a, b)\n#{body}  end\nend\n")
      described_class.new.call(Evilution::AST::Parser.new.call(file.path).first)
    end
  end

  # The body of the method after each mutation.
  def mutated_bodies(body)
    mutations_of(body).map { |m| m.mutated_source.lines[2..-3].join }
  end

  describe "#call" do
    it "replaces a plain call with safe navigation" do
      expect(mutated_bodies("    a.name\n")).to eq(["    a&.name\n"])
    end

    it "keeps the arguments and the block" do
      expect(mutated_bodies("    a.fetch(b, 1)\n")).to eq(["    a&.fetch(b, 1)\n"])
      expect(mutated_bodies("    a.each { |x| x }\n")).to eq(["    a&.each { |x| x }\n"])
    end

    it "mutates each link of a chain separately" do
      expect(mutated_bodies("    a.name.size\n")).to eq(["    a.name&.size\n", "    a&.name.size\n"])
    end

    it "mutates the plain links after a safe one" do
      expect(mutated_bodies("    a&.name.size\n")).to eq(["    a&.name&.size\n"])
    end

    it "mutates an attribute write and the compound writes" do
      expect(mutated_bodies("    a.name = b\n")).to eq(["    a&.name = b\n"])
      expect(mutated_bodies("    a.name ||= 1\n")).to eq(["    a&.name ||= 1\n"])
      expect(mutated_bodies("    a.name &&= 1\n")).to eq(["    a&.name &&= 1\n"])
      expect(mutated_bodies("    a.count += 1\n")).to eq(["    a&.count += 1\n"])
    end

    it "descends into the value of a compound write" do
      expect(mutated_bodies("    a.name ||= b.name\n")).to eq(["    a&.name ||= b.name\n", "    a.name ||= b&.name\n"])
      expect(mutated_bodies("    a.name &&= b.name\n")).to eq(["    a&.name &&= b.name\n", "    a.name &&= b&.name\n"])
      expect(mutated_bodies("    a.count += b.count\n")).to eq(["    a&.count += b.count\n", "    a.count += b&.count\n"])
    end

    it "mutates a call on an instance variable or on a call result" do
      expect(mutated_bodies("    @user.name\n")).to eq(["    @user&.name\n"])
      expect(mutated_bodies("    find(a).name\n")).to eq(["    find(a)&.name\n"])
    end

    it "emits nothing for a call without a receiver or without a dot" do
      expect(mutations_of("    name\n    find(a)\n    a + b\n    a[0]\n    !a\n")).to be_empty
    end

    it "emits nothing for a call that is already safe" do
      expect(mutations_of("    a&.name\n")).to be_empty
    end

    it "skips a self receiver, which is never nil" do
      expect(mutations_of("    self.name\n")).to be_empty
    end

    it "skips literal receivers, which are never nil" do
      body = "    \"x\".size\n    [a].first\n    { a: 1 }.keys\n    1.succ\n    :a.to_proc\n    /x/.source\n    1.5.round\n"

      expect(mutations_of(body)).to be_empty
    end

    it "skips a constant receiver" do
      expect(mutations_of("    File.read(a)\n    Evilution::Config.new\n")).to be_empty
    end

    it "leaves a `::` call alone" do
      expect(mutations_of("    a::name\n")).to be_empty
    end

    it "still mutates a call on nil itself" do
      expect(mutated_bodies("    nil.to_a\n")).to eq(["    nil&.to_a\n"])
    end

    it "reports the mutation on the line of the call" do
      expect(mutations_of("    b\n    a.name\n").map(&:line)).to eq([4])
    end

    it "produces valid Ruby" do
      bodies = ["    a.name.size\n", "    a.name = b\n", "    a.count += 1\n", "    a.each { |x| x.name }\n",
                "    a.()\n", "    a.+(b)\n", "    record a.name, b.name\n", "    a.name if b.ready?\n"]
      mutations = bodies.flat_map { |body| mutations_of(body) }

      expect(mutations).not_to be_empty
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      expect(mutations_of("    a.name\n").map(&:operator_name)).to eq(["safe_navigation_insertion"])
    end
  end
end
