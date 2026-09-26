# frozen_string_literal: true

RSpec.describe Evilution::Mutator::Operator::CollectionReplacement do
  let(:fixture_path) { File.expand_path("../../../support/fixtures/collection.rb", __dir__) }
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

  describe "#call" do
    it "replaces map with each" do
      muts = mutations_for("transform")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.each")
    end

    it "replaces each with map" do
      muts = mutations_for("iterate")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.map")
    end

    it "replaces select with reject" do
      muts = mutations_for("filter_in")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.reject")
    end

    it "replaces reject with select" do
      muts = mutations_for("filter_out")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.select")
    end

    it "replaces flat_map with map" do
      muts = mutations_for("flatten_transform")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.map")
    end

    it "replaces collect with each" do
      muts = mutations_for("collect_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.each")
    end

    it "replaces sort with sort_by" do
      muts = mutations_for("sort_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.sort_by")
    end

    it "replaces sort_by with sort" do
      muts = mutations_for("sort_by_items")

      sort_mut = muts.find { |m| m.mutated_source.include?("items.sort {") }
      expect(sort_mut).not_to be_nil
    end

    it "also replaces length inside sort_by block" do
      muts = mutations_for("sort_by_items")

      count_mut = muts.find { |m| m.mutated_source.include?("i.count") }
      expect(count_mut).not_to be_nil
    end

    it "replaces find with detect" do
      muts = mutations_for("find_item")

      expect(muts.map(&:mutated_source)).to include(a_string_including("items.detect"))
    end

    it "replaces detect with find" do
      muts = mutations_for("detect_item")

      expect(muts.map(&:mutated_source)).to include(a_string_including("items.find"))
    end

    it "replaces any? with all?" do
      muts = mutations_for("check_any")

      expect(muts.map(&:mutated_source)).to include(a_string_including("items.all?"))
    end

    it "replaces all? with any?" do
      muts = mutations_for("check_all")

      expect(muts.map(&:mutated_source)).to include(a_string_including("items.any?"))
    end

    it "replaces count with length" do
      muts = mutations_for("count_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.length")
    end

    it "replaces length with count" do
      muts = mutations_for("length_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.count")
    end

    it "replaces pop with shift" do
      muts = mutations_for("pop_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.shift")
    end

    it "replaces shift with pop" do
      muts = mutations_for("shift_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.pop")
    end

    it "replaces push with unshift" do
      muts = mutations_for("push_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.unshift")
    end

    it "replaces unshift with push" do
      muts = mutations_for("unshift_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.push")
    end

    it "replaces each_key with each_value" do
      muts = mutations_for("iterate_keys")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.each_value")
    end

    it "replaces each_value with each_key" do
      muts = mutations_for("iterate_values")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.each_key")
    end

    it "replaces assoc with rassoc" do
      muts = mutations_for("assoc_lookup")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.rassoc")
    end

    it "replaces rassoc with assoc" do
      muts = mutations_for("rassoc_lookup")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.assoc")
    end

    it "replaces grep with grep_v" do
      muts = mutations_for("grep_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.grep_v")
    end

    it "replaces grep_v with grep" do
      muts = mutations_for("grep_v_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.grep(")
    end

    it "replaces take with drop" do
      muts = mutations_for("take_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.drop")
    end

    it "replaces drop with take" do
      muts = mutations_for("drop_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.take")
    end

    it "replaces min with max" do
      muts = mutations_for("min_item")

      expect(muts.map(&:mutated_source)).to include(a_string_including("items.max"))
    end

    it "replaces max with min" do
      muts = mutations_for("max_item")

      expect(muts.map(&:mutated_source)).to include(a_string_including("items.min"))
    end

    it "replaces min_by with max_by" do
      muts = mutations_for("min_by_item")
      swap = muts.find { |m| m.mutated_source.include?("items.max_by") }

      expect(swap).not_to be_nil
    end

    it "replaces max_by with min_by" do
      muts = mutations_for("max_by_item")
      swap = muts.find { |m| m.mutated_source.include?("items.min_by") }

      expect(swap).not_to be_nil
    end

    it "replaces compact with flatten" do
      muts = mutations_for("compact_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.flatten")
    end

    it "replaces flatten with compact" do
      muts = mutations_for("flatten_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.compact")
    end

    it "replaces zip with product" do
      muts = mutations_for("zip_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a.product")
    end

    it "replaces product with zip" do
      muts = mutations_for("product_items")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("a.zip")
    end

    it "replaces first with last" do
      muts = mutations_for("first_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.last")
    end

    it "replaces last with first" do
      muts = mutations_for("last_item")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("items.first")
    end

    it "replaces keys with values" do
      muts = mutations_for("hash_keys")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.values")
    end

    it "replaces values with keys" do
      muts = mutations_for("hash_values")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("hash.keys")
    end

    it "produces valid Ruby for all mutations" do
      subjects_from_fixture.each do |subj|
        muts = described_class.new.call(subj)
        muts.each do |mutation|
          expect { Prism.parse(mutation.mutated_source) }.not_to raise_error,
                                                                 "Invalid Ruby produced for #{mutation}"
        end
      end
    end

    it "sets correct operator_name" do
      muts = mutations_for("transform")

      muts.each do |mutation|
        expect(mutation.operator_name).to eq("collection_replacement")
      end
    end

    it "does not mutate methods with no collection operators" do
      plain_source = "class Foo\n  def greet\n    'hello'\n  end\nend"
      tree = Prism.parse(plain_source).value
      finder = Evilution::AST::SubjectFinder.new(plain_source, fixture_path)
      finder.visit(tree)
      subj = finder.subjects.find { |s| s.name.end_with?("#greet") }

      muts = described_class.new.call(subj)
      expect(muts).to be_empty
    end

    def replaced_selectors(src)
      Tempfile.create(["collection_replacement", ".rb"]) do |tmpfile|
        tmpfile.write("def t(x)\n  #{src}\nend\n")
        tmpfile.flush
        subjects = Evilution::AST::Parser.new.call(tmpfile.path)
        subjects.flat_map { |s| described_class.new.call(s) }.map { |m| m.mutated_slice[/x\.(\w+[?!]?)/, 1] }
      end
    end

    # Selection and lookup pairs (EV-tsi4.25) and argument-free traversals
    # to each (EV-tsi4.24), with the full replacement set
    # per selector so emission order does not matter.
    {
      "any?" => %w[all? empty? none?],
      "all?" => %w[any? none?],
      "find" => %w[detect first last],
      "detect" => %w[find first last],
      "max" => %w[min first last],
      "min" => %w[max first last],
      "sample" => %w[first last],
      "max_by" => %w[min_by first last],
      "min_by" => %w[max_by first last],
      "fetch" => %w[key?],
      "at" => %w[fetch key?],
      "delete_if" => %w[reject],
      "keep_if" => %w[select],
      "filter_map" => %w[map],
      "sort_by" => %w[sort],
      "chunk" => %w[each],
      "chunk_while" => %w[each],
      "each_with_index" => %w[each],
      "slice_when" => %w[each]
    }.each do |selector, replacements|
      it "replaces #{selector} with #{replacements.join(", ")}" do
        expect(replaced_selectors("x.#{selector}")).to match_array(replacements)
      end
    end

    # `each` takes no arguments: `each(2) { }` would only ever raise
    # ArgumentError, killed by mere execution.
    %w[each_slice(2) each_cons(2) each_with_object([]) slice_before(1) slice_after(1)].each do |call|
      it "leaves the argument-taking traversal #{call} alone" do
        expect(replaced_selectors("x.#{call}")).to be_empty
      end
    end

    it "still visits a replaceable call nested inside a non-replaceable call" do
      # `helper(items.map { ... })`: `helper` is not in the replacement table,
      # but the operator must keep traversing so the nested `items.map` call
      # is still replaced with `each`.
      muts = mutations_for("non_replaceable_wrapping_call")

      expect(muts.length).to eq(1)
      expect(muts.first.mutated_source).to include("helper(items.each {")
    end
  end
end
