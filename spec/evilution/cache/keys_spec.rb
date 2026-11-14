# frozen_string_literal: true

require "tmpdir"

RSpec.describe Evilution::Cache::Keys do
  around do |example|
    Dir.mktmpdir("evilution_keys") { |dir| Dir.chdir(dir) { example.run } }
  end

  let(:source) do
    <<~RUBY
      class Shop
        RATE = 2

        def price(n)
          n * RATE
        end

        def label
          "shop"
        end
      end
    RUBY
  end

  let(:selector) { ->(_path) { ["spec/shop_spec.rb"] } }
  let(:fingerprint) { "run-a" }

  before do
    FileUtils.mkdir_p(%w[lib spec])
    File.write("spec/shop_spec.rb", "spec")
  end

  def keys(fingerprint: self.fingerprint, spec_selector: selector, related_specs: nil)
    described_class.new(fingerprint: fingerprint, spec_selector: spec_selector, related_specs: related_specs)
  end

  def parse(text)
    File.write("lib/shop.rb", text)
    Evilution::AST::Parser.new.call("lib/shop.rb")
  end

  # A mutation of `subject` replacing the first `from` inside it with `to`.
  def mutate(text, subject, from, to, operator: "op")
    offset = subject.byte_range.begin + subject.source.index(from)
    line_start = text.rindex("\n", offset).to_i + 1
    slice = slice_at(text, line_start, offset, from, to)
    Evilution::Mutation.new(
      subject: subject, operator_name: operator,
      sources: Evilution::Mutation::Sources.new(original: text, mutated: text.sub(slice.original, slice.mutated)),
      slice: slice, location: location(text, offset, line_start)
    )
  end

  def slice_at(text, line_start, offset, from, to)
    original = text.byteslice(line_start...(text.index("\n", offset) + 1))
    Evilution::Mutation::Slice.new(original: original, mutated: original.sub(from, to))
  end

  def location(text, offset, line_start)
    Evilution::Mutation::Location.new(file_path: "lib/shop.rb", line: text.byteslice(0, offset).count("\n") + 1,
                                      column: offset - line_start)
  end

  def subject_named(subjects, name)
    subjects.find { |s| s.name == name }
  end

  def key_of(text, name, from, to, keys: self.keys)
    subjects = parse(text)
    keys.index(subjects)
    mutation = mutate(text, subject_named(subjects, name), from, to)
    [keys.subject_key(mutation), keys.mutation_key(mutation)]
  end

  describe ".for" do
    def config(**options)
      Evilution::Config.new(skip_config_file: true, spec_files: ["spec/shop_spec.rb"], **options)
    end

    def keys_for_config(cfg)
      keys = described_class.for(cfg)
      subjects = parse(source)
      keys.index(subjects)
      mutation = mutate(source, subject_named(subjects, "Shop#price"), "*", "/")
      [keys.subject_key(mutation), keys.mutation_key(mutation)]
    end

    it "keys by the spec files the config resolves" do
      before = keys_for_config(config).first
      File.write("spec/shop_spec.rb", "spec 2")

      expect(keys_for_config(config).first).not_to be_nil
      expect(keys_for_config(config).first).not_to eq(before)
    end

    it "keys alike for alike configs" do
      expect(keys_for_config(config)).to eq(keys_for_config(config))
    end

    it "keys by the config's settings" do
      expect(keys_for_config(config(timeout: 5)).first).not_to eq(keys_for_config(config(timeout: 6)).first)
    end

    it "takes in the related spec files only when the heuristic is on" do
      source = "class Shop\n  def all\n    Shop.includes(:items)\n  end\nend\n"
      FileUtils.mkdir_p("spec/requests")
      File.write("spec/requests/shop_spec.rb", "1")
      key = lambda do |cfg|
        keys = described_class.for(cfg)
        subjects = parse(source)
        keys.index(subjects)
        keys.mutation_key(mutate(source, subject_named(subjects, "Shop#all"), ".includes(:items)", ""))
      end

      on = key.call(config(related_specs_heuristic: true))
      File.write("spec/requests/shop_spec.rb", "2")

      expect(key.call(config(related_specs_heuristic: true))).not_to eq(on)
      expect(key.call(config)).to eq(key.call(config))
      expect(key.call(config).split(":").length).to eq(3)
    end
  end

  describe "#subject_key" do
    it "stays the same when another method of the file is edited" do
      edited = source.sub("\"shop\"", "\"store\"\n    # more\n    \"shop\"")

      expect(key_of(edited, "Shop#price", "*", "/")).to eq(key_of(source, "Shop#price", "*", "/"))
    end

    it "stays the same when the subject moves because a method above it grew" do
      edited = source.sub("    n * RATE\n", "    # a\n    # b\n    n * RATE\n")

      expect(key_of(edited, "Shop#label", "shop", "x").first).to eq(key_of(source, "Shop#label", "shop", "x").first)
    end

    it "answers the same key for a subject asked again" do
      subjects = parse(source)
      keys = self.keys
      keys.index(subjects)
      mutation = mutate(source, subject_named(subjects, "Shop#price"), "*", "/")
      first = keys.subject_key(mutation)

      expect(first).not_to be_nil
      expect(keys.subject_key(mutation)).to eq(first)
    end

    it "keys each file by its own skeleton" do
      keys = self.keys
      File.write("lib/other.rb", source.sub("RATE = 2", "RATE = 3"))
      other_subjects = Evilution::AST::Parser.new.call("lib/other.rb")
      subjects = parse(source)
      keys.index(subjects + other_subjects)
      other_source = File.read("lib/other.rb")
      price = subject_named(other_subjects, "Shop#price")
      offset = price.byte_range.begin + price.source.index("*")
      line_start = other_source.rindex("\n", offset) + 1
      other = Evilution::Mutation.new(
        subject: price, operator_name: "op",
        sources: Evilution::Mutation::Sources.new(original: other_source, mutated: other_source),
        slice: slice_at(other_source, line_start, offset, "*", "/"),
        location: Evilution::Mutation::Location.new(file_path: "lib/other.rb", line: 5, column: 6)
      )
      keys.subject_key(mutate(source, subject_named(subjects, "Shop#price"), "*", "/"))

      expect(keys.subject_key(other)).to eq(keys(spec_selector: selector).tap { |k| k.index(other_subjects) }.subject_key(other))
    end

    it "tells apart the subjects of a file" do
      subjects = parse(source)
      keys = self.keys
      keys.index(subjects)
      price = keys.subject_key(mutate(source, subject_named(subjects, "Shop#price"), "*", "/"))
      label = keys.subject_key(mutate(source, subject_named(subjects, "Shop#label"), "shop", "x"))

      expect(price).not_to eq(label)
    end

    it "changes when a constant defined by a call is edited" do
      with_point = source.sub("RATE = 2\n", "RATE = 2\n  Point = Data.define(:x)\n")
      edited = with_point.sub("Data.define(:x)", "Data.define(:x, :y)")

      expect(key_of(edited, "Shop#price", "*", "/").first).not_to eq(key_of(with_point, "Shop#price", "*", "/").first)
    end

    it "asks the spec selector about the mutation's file" do
      keys = keys(spec_selector: ->(path) { path == "lib/shop.rb" ? ["spec/shop_spec.rb"] : nil })

      expect(key_of(source, "Shop#price", "*", "/", keys: keys).first).not_to be_nil
    end

    it "changes when the subject itself is edited" do
      edited = source.sub("n * RATE", "n * RATE + 0")

      expect(key_of(edited, "Shop#price", "*", "/").first).not_to eq(key_of(source, "Shop#price", "*", "/").first)
    end

    it "changes when code outside every subject is edited" do
      edited = source.sub("class Shop", "class Shop\n  include Comparable")

      expect(key_of(edited, "Shop#price", "*", "/").first).not_to eq(key_of(source, "Shop#price", "*", "/").first)
    end

    it "changes when a constant the subject reads is edited" do
      edited = source.sub("RATE = 2", "RATE = 3")

      expect(key_of(edited, "Shop#price", "*", "/").first).not_to eq(key_of(source, "Shop#price", "*", "/").first)
    end

    it "changes when a resolved spec file changes" do
      before = key_of(source, "Shop#price", "*", "/").first
      File.write("spec/shop_spec.rb", "spec 2")

      expect(key_of(source, "Shop#price", "*", "/").first).not_to eq(before)
    end

    it "changes with the run's fingerprint" do
      expect(key_of(source, "Shop#price", "*", "/", keys: keys(fingerprint: "run-b")).first)
        .not_to eq(key_of(source, "Shop#price", "*", "/").first)
    end

    it "is nil when no spec file resolves for the source" do
      keys = keys(spec_selector: ->(_path) {})

      expect(key_of(source, "Shop#price", "*", "/", keys: keys).first).to be_nil
    end

    it "is nil once the mutation's sources are released" do
      subjects = parse(source)
      keys.index(subjects)
      mutation = mutate(source, subject_named(subjects, "Shop#price"), "*", "/")
      mutation.strip_sources!

      expect(keys.subject_key(mutation)).to be_nil
    end

    it "keys the whole file when its subjects were not indexed" do
      subjects = parse(source)
      unindexed = keys
      mutation = mutate(source, subject_named(subjects, "Shop#price"), "*", "/")
      key = unindexed.subject_key(mutation)

      edited = source.sub("\"shop\"", "\"store\"")
      other = parse(edited)
      moved = mutate(edited, subject_named(other, "Shop#price"), "*", "/")

      expect(keys.subject_key(moved)).not_to eq(key)
    end
  end

  describe "#mutation_key" do
    it "stays the same when the subject moves within the file" do
      edited = source.sub("    n * RATE\n", "    # a\n    # b\n    n * RATE\n")

      expect(key_of(edited, "Shop#label", "shop", "x").last).to eq(key_of(source, "Shop#label", "shop", "x").last)
    end

    it "tells apart the same edit on two identical lines" do
      twice = source.sub("    n * RATE\n", "    n * RATE\n    n * RATE\n")
      subjects = parse(twice)
      price = subject_named(subjects, "Shop#price")
      first = mutate(twice, price, "*", "/")
      offset = price.byte_range.begin + price.source.rindex("*")
      line_start = twice.rindex("\n", offset) + 1
      second = Evilution::Mutation.new(
        subject: price, operator_name: "op",
        sources: Evilution::Mutation::Sources.new(original: twice, mutated: twice),
        slice: first.instance_variable_get(:@slice), location: location(twice, offset, line_start)
      )

      expect(keys.mutation_key(first)).not_to eq(keys.mutation_key(second))
    end

    it "keys a mutation built without a slice by its mutated file" do
      subjects = parse(source)
      price = subject_named(subjects, "Shop#price")
      unsliced = lambda do |mutated|
        Evilution::Mutation.new(
          subject: price, operator_name: "op",
          sources: Evilution::Mutation::Sources.new(original: source, mutated: mutated),
          location: Evilution::Mutation::Location.new(file_path: "lib/shop.rb", line: 5, column: 6)
        )
      end

      expect(keys.mutation_key(unsliced.call(source.sub("*", "/"))))
        .not_to eq(keys.mutation_key(unsliced.call(source.sub("*", "+"))))
    end

    it "tells apart two mutations at the same place" do
      expect(key_of(source, "Shop#price", "*", "/").last).not_to eq(key_of(source, "Shop#price", "*", "+").last)
    end

    it "tells apart operators" do
      subjects = parse(source)
      price = subject_named(subjects, "Shop#price")

      expect(keys.mutation_key(mutate(source, price, "*", "/", operator: "a")))
        .not_to eq(keys.mutation_key(mutate(source, price, "*", "/", operator: "b")))
    end

    it "is nil once the mutation's sources are released" do
      subjects = parse(source)
      mutation = mutate(source, subject_named(subjects, "Shop#price"), "*", "/")
      mutation.strip_sources!

      expect(keys.mutation_key(mutation)).to be_nil
    end

    it "leaves the related spec files out when the heuristic adds none" do
      related = ->(_mutation) { [] }

      expect(key_of(source, "Shop#price", "*", "/", keys: keys(related_specs: related)).last)
        .to eq(key_of(source, "Shop#price", "*", "/").last)
    end

    it "takes in the related spec files when the heuristic adds them" do
      File.write("spec/related_spec.rb", "1")
      related = ->(mutation) { mutation.is_a?(Evilution::Mutation) ? ["spec/related_spec.rb"] : [] }
      before = key_of(source, "Shop#price", "*", "/", keys: keys(related_specs: related)).last
      File.write("spec/related_spec.rb", "2")

      expect(key_of(source, "Shop#price", "*", "/", keys: keys(related_specs: related)).last).not_to eq(before)
    end
  end

  describe "#subject_names" do
    it "lists the names of the indexed subjects of a file" do
      keys = self.keys
      keys.index(parse(source))

      expect(keys.subject_names("lib/shop.rb")).to contain_exactly("Shop#price", "Shop#label", "Shop::RATE")
    end

    it "is nil for a file that was not indexed" do
      expect(keys.subject_names("lib/other.rb")).to be_nil
    end
  end
end
