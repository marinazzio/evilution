# frozen_string_literal: true

require "tempfile"

RSpec.describe Evilution::AST::Parser do
  subject(:parser) { described_class.new }

  let(:fixture_path) { File.expand_path("../../support/fixtures/simple_class.rb", __dir__) }

  describe "#call" do
    it "returns an array of Subject objects" do
      subjects = parser.call(fixture_path)

      expect(subjects).to all(be_a(Evilution::Subject))
    end

    it "extracts all method definitions" do
      subjects = parser.call(fixture_path)
      names = subjects.map(&:name)

      expect(names).to contain_exactly(
        "User#initialize",
        "User#adult?",
        "User#greeting",
        "Admin#admin?"
      )
    end

    it "sets correct file path on each subject" do
      subjects = parser.call(fixture_path)

      subjects.each do |subject|
        expect(subject.file_path).to eq(fixture_path)
      end
    end

    it "sets correct line numbers" do
      subjects = parser.call(fixture_path)
      lines = subjects.to_h { |s| [s.name, s.line_number] }

      expect(lines["User#initialize"]).to eq(4)
      expect(lines["User#adult?"]).to eq(9)
      expect(lines["User#greeting"]).to eq(13)
      expect(lines["Admin#admin?"]).to eq(19)
    end

    it "captures method source code" do
      subjects = parser.call(fixture_path)
      adult_subject = subjects.find { |s| s.name == "User#adult?" }

      expect(adult_subject.source).to include("def adult?")
      expect(adult_subject.source).to include("@age >= 18")
    end

    it "stores the Prism DefNode" do
      subjects = parser.call(fixture_path)

      subjects.each do |subject|
        expect(subject.node).to be_a(Prism::DefNode)
      end
    end
  end

  describe "#call error handling" do
    it "raises ParseError when the file does not exist" do
      missing = File.join(Dir.tmpdir, "evilution_does_not_exist_#{Process.pid}.rb")

      expect { parser.call(missing) }
        .to raise_error(Evilution::ParseError, /file not found: #{Regexp.escape(missing)}/)
    end

    it "raises ParseError when the source cannot be parsed" do
      tmpfile = Tempfile.new(["broken", ".rb"])
      tmpfile.write("def foo(\n")
      tmpfile.close

      expect { parser.call(tmpfile.path) }
        .to raise_error(Evilution::ParseError, /failed to parse/)
    ensure
      tmpfile&.unlink
    end

    it "includes the underlying parse error messages in the ParseError" do
      tmpfile = Tempfile.new(["broken", ".rb"])
      tmpfile.write("def foo(\n")
      tmpfile.close

      expected_messages = Prism.parse(File.read(tmpfile.path)).errors.map(&:message)
      joined = expected_messages.join(", ")

      expect { parser.call(tmpfile.path) }
        .to raise_error(Evilution::ParseError) { |error|
          expect(error.message).to include(joined)
          expect(error.message).not_to include("[\"")
        }
    ensure
      tmpfile&.unlink
    end
  end

  context "with nested modules" do
    let(:nested_source) do
      <<~RUBY
        module Foo
          class Bar
            def baz
              42
            end
          end
        end
      RUBY
    end

    it "builds fully-qualified names" do
      tmpfile = Tempfile.new(["nested", ".rb"])
      tmpfile.write(nested_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("Foo::Bar#baz")
    ensure
      tmpfile&.unlink
    end
  end

  context "with sibling nested classes" do
    let(:siblings_source) do
      <<~RUBY
        module Outer
          class First
            def one
              1
            end
          end

          class Second
            def two
              2
            end
          end
        end
      RUBY
    end

    it "pops context so a later sibling is not polluted by an earlier one" do
      tmpfile = Tempfile.new(["siblings", ".rb"])
      tmpfile.write(siblings_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      names = subjects.map(&:name)

      expect(names).to contain_exactly("Outer::First#one", "Outer::Second#two")
    ensure
      tmpfile&.unlink
    end
  end

  context "with a method nested inside another method" do
    let(:nested_def_source) do
      <<~RUBY
        class Builder
          def outer
            def inner
              :inner
            end
          end
        end
      RUBY
    end

    it "descends into the body and finds inner method definitions" do
      tmpfile = Tempfile.new(["nested_def", ".rb"])
      tmpfile.write(nested_def_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      names = subjects.map(&:name)

      expect(names).to include("Builder#inner")
    ensure
      tmpfile&.unlink
    end
  end

  context "with a constant path node lacking #full_name" do
    it "falls back to a String name when the node does not respond to full_name" do
      fake_node = Struct.new(:name).new(:Widget)
      finder = Evilution::AST::SubjectFinder.new("", "fake.rb")
      result = finder.send(:constant_name, fake_node)

      expect(result).to eq("Widget")
      expect(result).to be_a(String)
    end
  end

  context "with compact class notation" do
    let(:compact_source) do
      <<~RUBY
        class Foo::Bar
          def baz
            42
          end
        end
      RUBY
    end

    it "handles Foo::Bar style class names" do
      tmpfile = Tempfile.new(["compact", ".rb"])
      tmpfile.write(compact_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("Foo::Bar#baz")
    ensure
      tmpfile&.unlink
    end
  end

  context "with a class or module whose path has dynamic parts" do
    it "names it within the scope it is written in" do
      tmpfile = Tempfile.new(["dynamic_path", ".rb"])
      tmpfile.write(<<~RUBY)
        module Units
          class self::Meter
            def scale
              1
            end
          end

          module self::Helpers
            def help
              :ok
            end
          end
        end
      RUBY
      tmpfile.close

      names = parser.call(tmpfile.path).map(&:name)

      expect(names).to contain_exactly("Units::Meter#scale", "Units::Helpers#help")
    ensure
      tmpfile&.unlink
    end
  end

  context "with class methods (def self.foo)" do
    let(:class_method_source) do
      <<~RUBY
        class Service
          def self.call(input)
            new(input).run
          end

          def run
            :ok
          end
        end
      RUBY
    end

    it "names class methods with dot separator" do
      tmpfile = Tempfile.new(["class_method", ".rb"])
      tmpfile.write(class_method_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      names = subjects.map(&:name)

      expect(names).to contain_exactly("Service.call", "Service#run")
    ensure
      tmpfile&.unlink
    end

    it "captures class method source" do
      tmpfile = Tempfile.new(["class_method", ".rb"])
      tmpfile.write(class_method_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      call_subject = subjects.find { |s| s.name == "Service.call" }

      expect(call_subject.source).to include("def self.call")
    ensure
      tmpfile&.unlink
    end
  end

  context "with methods inside class << self" do
    def subject_names(source)
      tmpfile = Tempfile.new(["singleton_class", ".rb"])
      tmpfile.write(source)
      tmpfile.close

      parser.call(tmpfile.path).map(&:name)
    ensure
      tmpfile&.unlink
    end

    it "names them with dot separator" do
      names = subject_names(<<~RUBY)
        class Gateway
          class << self
            def create_group(owner)
              owner
            end

            private

            def build(path)
              path
            end
          end

          def run
            :ok
          end
        end
      RUBY

      expect(names).to contain_exactly("Gateway.create_group", "Gateway.build", "Gateway#run")
    end

    it "names them within a nested module" do
      names = subject_names(<<~RUBY)
        module Api
          module Client
            class << self
              def fetch
                :ok
              end
            end
          end
        end
      RUBY

      expect(names).to contain_exactly("Api::Client.fetch")
    end

    it "names instance methods after the singleton block with hash separator" do
      names = subject_names(<<~RUBY)
        class Gateway
          class << self
            def one
              1
            end
          end

          def two
            2
          end
        end
      RUBY

      expect(names).to contain_exactly("Gateway.one", "Gateway#two")
    end

    it "names methods of a class defined inside the singleton block as instance methods" do
      names = subject_names(<<~RUBY)
        class Outer
          class << self
            class Inner
              def call
                :ok
              end
            end
          end
        end
      RUBY

      expect(names).to contain_exactly("Outer::Inner#call")
    end

    it "names methods of class << Constant after that constant" do
      names = subject_names(<<~RUBY)
        module Registry
          class << Store
            def lookup
              :ok
            end
          end

          def self.reset
            :ok
          end
        end
      RUBY

      expect(names).to contain_exactly("Registry::Store.lookup", "Registry.reset")
    end

    it "names methods of class << Namespaced::Constant after that path" do
      names = subject_names(<<~RUBY)
        class << Cache::Store
          def lookup
            :ok
          end
        end
      RUBY

      expect(names).to contain_exactly("Cache::Store.lookup")
    end

    it "names methods of class << self::Constant after the constant's own name" do
      names = subject_names(<<~RUBY)
        module Units
          class << self::Meter
            def scale
              1
            end
          end
        end
      RUBY

      expect(names).to contain_exactly("Units::Meter.scale")
    end

    it "names methods of a module defined inside the singleton block as instance methods" do
      names = subject_names(<<~RUBY)
        class Outer
          class << self
            module Helpers
              def help
                :ok
              end
            end
          end
        end
      RUBY

      expect(names).to contain_exactly("Outer::Helpers#help")
    end
  end

  context "with scope declarations in a class body" do
    def scope_subjects(source)
      tmpfile = Tempfile.new(["scopes", ".rb"])
      tmpfile.write(source)
      tmpfile.close

      parser.call(tmpfile.path).select { |s| s.kind == :scope }
    ensure
      tmpfile.unlink if tmpfile
    end

    it "makes a subject named after the class method the scope defines" do
      subjects = scope_subjects(<<~RUBY)
        module Shop
          class Order
            scope :for_owner, ->(owner) { owner ? where(owner: owner) : none }
          end
        end
      RUBY

      expect(subjects.map(&:name)).to eq(["Shop::Order.for_owner"])
    end

    it "spans the whole scope call and mutates the lambda" do
      subjects = scope_subjects(<<~RUBY)
        class Order
          scope :recent,
                -> { where(recent: true) }
        end
      RUBY

      subject = subjects.first
      expect([subject.line_number, subject.source]).to eq([2, "scope :recent,\n        -> { where(recent: true) }"])
      expect(subject.node).to be_a(Prism::LambdaNode)
    end

    it "mutates the block of a lambda or proc call" do
      subjects = scope_subjects(<<~RUBY)
        class Order
          scope :paid, lambda { where(paid: true) }
          scope :open, proc { where(open: true) }
        end
      RUBY

      expect(subjects.map(&:name)).to eq(["Order.paid", "Order.open"])
      expect(subjects.map(&:node)).to all(be_a(Prism::BlockNode))
    end

    it "skips scopes whose body is not a literal lambda" do
      subjects = scope_subjects(<<~RUBY)
        class Order
          scope :active, ActiveQuery
          scope :named, method(:build)
          scope :dynamic, :lambda_name
          scope name_var, -> { all }
        end
      RUBY

      expect(subjects).to be_empty
    end

    it "skips scope calls that are not direct statements of a class body" do
      subjects = scope_subjects(<<~RUBY)
        module Publishable
          scope :published, -> { where(published: true) }

          prepended do
            scope :drafts, -> { where(published: false) }
          end

          included do
            if legacy?
              scope :nested, -> { all }
            end
          end
        end

        class Order
          included do
            scope :stray, -> { all }
          end

          class << self
            scope :hidden, -> { all }
          end

          def self.build
            scope :inner, -> { all }
          end

          relation.scope :other, -> { all }
        end
      RUBY

      expect(subjects).to be_empty
    end

    it "keeps method subjects alongside scopes" do
      tmpfile = Tempfile.new(["scopes", ".rb"])
      tmpfile.write(<<~RUBY)
        class Order
          scope :paid, -> { where(paid: true) }

          def total
            1
          end
        end
      RUBY
      tmpfile.close

      expect(parser.call(tmpfile.path).map { |s| [s.name, s.kind] })
        .to eq([["Order.paid", :scope], ["Order#total", :method]])
    ensure
      tmpfile.unlink if tmpfile
    end
  end

  context "with value-object definitions outside any method" do
    def subjects_in(source)
      tmpfile = Tempfile.new(["value_objects", ".rb"])
      tmpfile.write(source)
      tmpfile.close
      parser.call(tmpfile.path)
    ensure
      tmpfile&.unlink
    end

    it "makes a constant subject of a top-level definition" do
      subjects = subjects_in("Point = Data.define(:x, :y)\n")

      expect(subjects.length).to eq(1)
      point = subjects.first
      expect(point.name).to eq("Point")
      expect(point.kind).to eq(:constant)
      expect(point.line_number).to eq(1)
      expect(point.source).to eq("Data.define(:x, :y)")
      expect(point.node).to be_a(Prism::CallNode)
    end

    it "qualifies the name with the enclosing scope" do
      subjects = subjects_in("module Geo\n  class Shape\n    Size = Struct.new(:w, :h)\n  end\nend\n")

      expect(subjects.map(&:name)).to eq(["Geo::Shape::Size"])
    end

    it "names a constant path assignment by its path" do
      subjects = subjects_in("module Geo; end\nGeo::Point = Data.define(:x, :y)\n")

      expect(subjects.map(&:name)).to eq(["Geo::Point"])
      expect(subjects.first.source).to eq("Data.define(:x, :y)")
      expect(subjects.first.node).to be_a(Prism::CallNode)
    end

    it "names a root constant path without the leading ::" do
      expect(subjects_in("::Point = Data.define(:x, :y)\n").map(&:name)).to eq(["Point"])
    end

    it "scopes the block of a constant path definition under its path" do
      subjects = subjects_in("Geo::Size = Struct.new(:w, :h) do\n  def area = w * h\nend\n")

      expect(subjects.map(&:name)).to eq(["Geo::Size", "Geo::Size#area"])
    end

    it "still finds methods in the value of other constants" do
      source = "Handler = Class.new do\n  def handle = 1\nend\nGeo::Tool = Class.new do\n  def use = 2\nend\nGeo::LIMIT = 5\n"

      expect(subjects_in(source).map { |s| [s.name, s.kind] }).to eq([["#handle", :method], ["#use", :method]])
    end

    it "makes a constant subject of a superclass definition, named after the class" do
      subjects = subjects_in("module Geo\n  class Coord < Data.define(:lat, :lng)\n    def north? = lat.positive?\n  end\nend\n")

      expect(subjects.map { |s| [s.name, s.kind] }).to eq([["Geo::Coord", :constant], ["Geo::Coord#north?", :method]])
      expect(subjects.first.source).to eq("Data.define(:lat, :lng)")
      expect(subjects.first.line_number).to eq(2)
    end

    it "covers the block and scopes what is defined in it under the constant" do
      source = "class Shape\n  Size = Struct.new(:w, :h) do\n    self::Unit = Data.define(:n, :s)\n\n    " \
               "def area = w * h\n  end\nend\n"
      subjects = subjects_in(source)

      expect(subjects.map { |s| [s.name, s.kind] }).to eq(
        [["Shape::Size", :constant], ["Shape::Size::Unit", :constant], ["Shape::Size#area", :method]]
      )
      expect(subjects.first.source).to start_with("Struct.new(:w, :h) do\n")
      expect(subjects.first.source).to end_with("end")
    end

    it "makes method subjects of kind :method" do
      expect(subjects_in("class Foo\n  def bar = 1\nend\n").map(&:kind)).to eq([:method])
    end

    it "ignores other constants and definitions not assigned to a constant" do
      source = "class Shape\n  LIMIT = 5\n  Other = Foo.new(:a, :b)\n  Struct.new(:a, :b).new(1, 2)\n  " \
               "Wrapped = Struct.new(:a, :b).freeze\n  class Sub < Base; end\nend\n"

      expect(subjects_in(source)).to be_empty
    end

    it "ignores a definition inside a method, which the method's subject covers" do
      subjects = subjects_in("class Foo\n  def build\n    Class.new { const_set(:P, Struct.new(:a, :b)) }\n  end\nend\n")

      expect(subjects.map(&:name)).to eq(["Foo#build"])
    end
  end

  context "with namespaced class methods" do
    let(:namespaced_class_method_source) do
      <<~RUBY
        module Api
          class Client
            def self.connect(url)
              new(url)
            end
          end
        end
      RUBY
    end

    it "builds fully-qualified names for class methods" do
      tmpfile = Tempfile.new(["ns_class_method", ".rb"])
      tmpfile.write(namespaced_class_method_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("Api::Client.connect")
    ensure
      tmpfile&.unlink
    end
  end

  context "with top-level methods" do
    let(:toplevel_source) do
      <<~RUBY
        def standalone
          "hello"
        end
      RUBY
    end

    it "uses just method name with hash prefix" do
      tmpfile = Tempfile.new(["toplevel", ".rb"])
      tmpfile.write(toplevel_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      expect(subjects.first.name).to eq("#standalone")
    ensure
      tmpfile&.unlink
    end
  end

  context "with multi-byte characters" do
    let(:multibyte_source) do
      # Cyrillic comment before the method to shift byte vs char offsets
      <<~RUBY
        class Greeter
          # Приветствие пользователя
          def greet(name)
            "Hello, \#{name}!"
          end
        end
      RUBY
    end

    it "extracts correct method source when file contains multi-byte characters" do
      tmpfile = Tempfile.new(["multibyte", ".rb"])
      tmpfile.write(multibyte_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      greet = subjects.find { |s| s.name == "Greeter#greet" }

      expect(greet).not_to be_nil
      expect(greet.source).to start_with("def greet(name)")
      expect(greet.source).to include("Hello")
      expect(greet.source).to end_with("end")
    ensure
      tmpfile&.unlink
    end

    it "preserves correct encoding in extracted source" do
      tmpfile = Tempfile.new(["multibyte", ".rb"])
      tmpfile.write(multibyte_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      greet = subjects.find { |s| s.name == "Greeter#greet" }

      expect(greet.source.encoding).to eq(Encoding::UTF_8)
      expect(greet.source).to be_valid_encoding
    ensure
      tmpfile&.unlink
    end

    it "extracts correct method source with Thai comments (3-byte UTF-8)" do
      thai_source = <<~RUBY
        class Calculator
          # คำนวณผลรวมของตัวเลข
          def sum(a, b)
            a + b
          end

          # ตรวจสอบว่าเป็นจำนวนคู่หรือไม่
          def even?(n)
            n.even?
          end
        end
      RUBY

      tmpfile = Tempfile.new(["thai", ".rb"])
      tmpfile.write(thai_source)
      tmpfile.close

      subjects = parser.call(tmpfile.path)
      sum_subject = subjects.find { |s| s.name == "Calculator#sum" }
      even_subject = subjects.find { |s| s.name == "Calculator#even?" }

      expect(sum_subject.source).to start_with("def sum(a, b)")
      expect(sum_subject.source).to include("a + b")
      expect(even_subject.source).to start_with("def even?(n)")
      expect(even_subject.source).to include("n.even?")
    ensure
      tmpfile&.unlink
    end
  end
  describe "AASM subjects" do
    def subjects_for(code)
      file = Tempfile.new(["aasm_model", ".rb"])
      file.write(code)
      file.close
      described_class.new.call(file.path)
    ensure
      file.unlink
    end

    let(:code) do
      <<~RUBY
        module Shop
          class Order
            aasm do
              state :paid, before_exit: -> { leaving }
              event :ship, guard: -> { address? } do
                transitions from: :paid, to: :shipped, guard: -> { ready? }
              end
            end

            def ready? = true
          end
        end
      RUBY
    end

    it "makes a subject of each guard and callback, named after the method its event or state defines" do
      subjects = subjects_for(code).select { |subject| subject.kind == :aasm }

      expect(subjects.map(&:name)).to eq(["Shop::Order#paid?", "Shop::Order#ship", "Shop::Order#ship"])
    end

    it "points each subject's node at the callable and spans its declaration" do
      subjects = subjects_for(code).select { |subject| subject.kind == :aasm }

      expect(subjects.map { |subject| subject.node.slice }).to eq(["-> { leaving }", "-> { address? }", "-> { ready? }"])
      expect(subjects.map(&:line_number)).to eq([4, 5, 5])
      expect(subjects.last.source).to start_with("event :ship").and end_with("end")
    end

    it "keeps the method subjects of the class" do
      expect(subjects_for(code).reject { |subject| subject.kind == :aasm }.map(&:name)).to eq(["Shop::Order#ready?"])
    end
  end

  describe "scope subjects in a concern's included block" do
    def subjects_for(code)
      file = Tempfile.new(["concern", ".rb"])
      file.write(code)
      file.close
      described_class.new.call(file.path)
    ensure
      file.unlink
    end

    let(:code) do
      <<~RUBY
        module Shop
          module Publishable
            extend ActiveSupport::Concern

            included do
              validates :title, presence: true
              scope :published, -> { where(published: true) }
              scope :named, by_name
            end

            scope :outside, -> { 1 }

            def publish! = true
          end
        end
      RUBY
    end

    it "makes a scope subject named after the concern" do
      scopes = subjects_for(code).select { |subject| subject.kind == :scope }

      expect(scopes.map(&:name)).to eq(["Shop::Publishable.published"])
      expect(scopes.first.node.slice).to eq("-> { where(published: true) }")
      expect(scopes.first.line_number).to eq(7)
      expect(scopes.first.source).to eq("scope :published, -> { where(published: true) }")
    end

    it "keeps the concern's methods as subjects" do
      expect(subjects_for(code).map(&:name)).to include("Shop::Publishable#publish!")
    end
  end

  describe "callback subjects" do
    def subjects_for(code)
      file = Tempfile.new(["callbacks", ".rb"])
      file.write(code)
      file.close
      described_class.new.call(file.path)
    ensure
      file.unlink
    end

    let(:code) do
      <<~RUBY
        module Shop
          class Order
            validate :credit_limit, if: -> { paid? }
            before_save do
              self.total = 0
            end
            before_save :named

            def paid? = true
          end
        end
      RUBY
    end

    it "makes a subject of each literal condition and callback, named as its declaration reads" do
      subjects = subjects_for(code).select { |subject| subject.kind == :callback }

      expect(subjects.map(&:name)).to eq(["Shop::Order.validate(:credit_limit)", "Shop::Order.before_save"])
      expect(subjects.map { |subject| subject.node.slice }).to eq(["-> { paid? }", "do\n      self.total = 0\n    end"])
    end

    it "spans the declaration" do
      subjects = subjects_for(code).select { |subject| subject.kind == :callback }

      expect(subjects.map(&:line_number)).to eq([3, 4])
      expect(subjects.last.source).to eq("before_save do\n      self.total = 0\n    end")
    end

    it "does not look inside a module body" do
      subjects = subjects_for("module Shop\n  before_save { 1 }\nend")

      expect(subjects).to eq([])
    end
  end

  describe "AASM subjects in a concern's included block" do
    def subjects_for(code)
      file = Tempfile.new(["shippable", ".rb"])
      file.write(code)
      file.close
      described_class.new.call(file.path)
    ensure
      file.unlink
    end

    let(:code) do
      <<~RUBY
        module Shippable
          extend ActiveSupport::Concern

          included do
            include AASM

            aasm do
              state :paid, before_exit: -> { leaving }
              event :ship, guard: -> { address? } do
                transitions from: :paid, to: :shipped
              end
            end
          end

          aasm do
            event :stray, guard: -> { 1 }
          end
        end
      RUBY
    end

    it "makes a subject of each guard and callback, named after the concern" do
      subjects = subjects_for(code).select { |subject| subject.kind == :aasm }

      expect(subjects.map(&:name)).to eq(["Shippable#paid?", "Shippable#ship"])
      expect(subjects.map { |subject| subject.node.slice }).to eq(["-> { leaving }", "-> { address? }"])
      expect(subjects.map(&:line_number)).to eq([8, 9])
    end
  end

  describe "callback subjects in a concern's included block" do
    def subjects_for(code)
      file = Tempfile.new(["publishable", ".rb"])
      file.write(code)
      file.close
      described_class.new.call(file.path)
    ensure
      file.unlink
    end

    let(:code) do
      <<~RUBY
        module Publishable
          extend ActiveSupport::Concern

          included do
            validates :title, presence: true, if: -> { published? }
            before_save { self.slug = title }
            before_save :named
          end

          before_save { 1 }
        end
      RUBY
    end

    it "makes a subject of each literal condition and callback, named after the concern" do
      subjects = subjects_for(code).select { |subject| subject.kind == :callback }

      expect(subjects.map(&:name)).to eq(["Publishable.validates(:title)", "Publishable.before_save"])
      expect(subjects.map { |subject| subject.node.slice }).to eq(["-> { published? }", "{ self.slug = title }"])
      expect(subjects.map(&:line_number)).to eq([5, 6])
    end
  end
end
