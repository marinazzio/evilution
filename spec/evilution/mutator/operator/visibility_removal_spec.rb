# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::VisibilityRemoval do
  def mutations_for(source, method_name = "first")
    Tempfile.create(["visibility_removal", ".rb"]) do |file|
      File.write(file.path, source)
      subject = Evilution::AST::Parser.new.call(file.path).find { |s| s.name.end_with?("##{method_name}", ".#{method_name}") }
      described_class.new.call(subject)
    end
  end

  # The source of each mutant with blank lines dropped, so an expectation
  # reads as the class that would load.
  def mutated_sources(source, method_name = "first")
    mutations_for(source, method_name).map { |m| m.mutated_source.lines.reject { |line| line.strip.empty? }.join }
  end

  describe "#call" do
    it "drops a bare private through the first method of the class" do
      source = "class Sample\n  def first = 1\n\n  private\n\n  def second = 2\nend\n"

      expect(mutated_sources(source)).to eq(["class Sample\n  def first = 1\n  def second = 2\nend\n"])
    end

    it "does not repeat the mutation for later methods" do
      source = "class Sample\n  def first = 1\n\n  private\n\n  def second = 2\nend\n"

      expect(mutations_for(source, "second")).to be_empty
    end

    it "drops protected and module_function" do
      expect(mutated_sources("class Sample\n  def first = 1\n  protected\n  def second = 2\nend\n"))
        .to eq(["class Sample\n  def first = 1\n  def second = 2\nend\n"])
      expect(mutated_sources("module Sample\n  module_function\n  def first = 1\nend\n"))
        .to eq(["module Sample\n  def first = 1\nend\n"])
    end

    it "drops each declaration in turn" do
      source = "class Sample\n  def first = 1\n  protected\n  def second = 2\n  private\n  def third = 3\nend\n"

      expect(mutated_sources(source)).to eq(
        ["class Sample\n  def first = 1\n  def second = 2\n  private\n  def third = 3\nend\n",
         "class Sample\n  def first = 1\n  protected\n  def second = 2\n  def third = 3\nend\n"]
      )
    end

    it "drops a declaration naming its methods" do
      expect(mutated_sources("class Sample\n  def first = 1\n  private :first, :second\nend\n"))
        .to eq(["class Sample\n  def first = 1\nend\n"])
      expect(mutated_sources("module Sample\n  def first = 1\n  module_function(:first)\nend\n"))
        .to eq(["module Sample\n  def first = 1\nend\n"])
      expect(mutated_sources("class Sample\n  def first = 1\n  private(*NAMES)\nend\n"))
        .to eq(["class Sample\n  def first = 1\nend\n"])
    end

    it "keeps the definition a declaration wraps" do
      expect(mutated_sources("class Sample\n  private def first = 1\nend\n")).to eq(["class Sample\n  def first = 1\nend\n"])
      expect(mutated_sources("class Sample\n  def first = 1\n  private def second\n    2\n  end\nend\n"))
        .to eq(["class Sample\n  def first = 1\n  def second\n    2\n  end\nend\n"])
      expect(mutated_sources("class Sample\n  def first = 1\n  protected(def second = 2)\nend\n"))
        .to eq(["class Sample\n  def first = 1\n  def second = 2\nend\n"])
    end

    it "keeps the attribute declaration a declaration wraps" do
      expect(mutated_sources("class Sample\n  def first = 1\n  private attr_reader :name\nend\n"))
        .to eq(["class Sample\n  def first = 1\n  attr_reader :name\nend\n"])
    end

    # `private helper_names` runs helper_names either way; only its result
    # stops being made private.
    it "keeps a bare call a declaration takes its names from" do
      expect(mutated_sources("class Sample\n  def first = 1\n  private helper_names\nend\n"))
        .to eq(["class Sample\n  def first = 1\n  helper_names\nend\n"])
    end

    it "leaves a declaration that wraps a definition among other arguments alone" do
      expect(mutations_for("class Sample\n  def first = 1\n  private attr_reader(:a), :b\nend\n")).to be_empty
      expect(mutations_for("class Sample\n  def first = 1\n  private :b, attr_reader(:a)\nend\n")).to be_empty
    end

    it "reaches a singleton class through its own first method" do
      source = "class Sample\n  class << self\n    def first = 1\n    private\n    def second = 2\n  end\nend\n"

      expect(mutated_sources(source)).to eq(["class Sample\n  class << self\n    def first = 1\n    def second = 2\n  end\nend\n"])
    end

    it "reports the mutation on the line of the declaration" do
      expect(mutations_for("class Sample\n  def first = 1\n\n  private\n\n  def second = 2\nend\n").map(&:line)).to eq([4])
    end

    it "leaves public and the other class-level declarations alone" do
      source = "class Sample\n  def first = 1\n  public\n  private_constant :A\n  private_class_method :new\n  attr_reader :a\nend\n"

      expect(mutations_for(source)).to be_empty
    end

    it "leaves a declaration sent to another receiver or guarded by a modifier alone" do
      source = "class Sample\n  def first = 1\n  self.private\n  Other.private :a\n  private :first if legacy?\nend\n"

      expect(mutations_for(source)).to be_empty
    end

    it "leaves a call inside a method alone" do
      expect(mutations_for("class Sample\n  def first\n    private\n  end\nend\n")).to be_empty
    end

    it "produces valid Ruby" do
      source = "class Sample\n  private def first = 1\n  protected\n  def second = 2\n  private :second\n  private attr_reader :a\nend\n"
      mutations = mutations_for(source)

      expect(mutations.length).to eq(4)
      expect(mutations.map(&:parse_status)).to all(eq(:ok))
    end

    it "sets correct operator_name" do
      mutations = mutations_for("class Sample\n  def first = 1\n  private\nend\n")

      expect(mutations.map(&:operator_name)).to eq(["visibility_removal"])
    end
  end
end
