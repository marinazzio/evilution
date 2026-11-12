# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"

# Applies a mutated validation the way a mutation run does -- the file is
# loaded, then its mutated source, neutralized, is evaluated under the same
# path -- against real ActiveModel, in a process of its own so its classes and
# what CallbackRedeclaration records do not outlive the example.
RSpec.describe "CallbackRedeclaration with ActiveModel" do
  let(:lib) { File.expand_path("../../../../lib", __dir__) }

  let(:script) do
    <<~'RUBY'
      require "json"
      require "active_model"
      require "evilution/integration/loading/body_call_neutralizer"

      path, original, mutated, checks = ARGV
      source = File.read(path)
      load path

      line = source[0, source.index(original)].count("\n") + 1
      mutated_source = source.sub(original, mutated)
      offset = mutated_source.index(mutated) + mutated.length - 1
      neutralized = Evilution::Integration::Loading::BodyCallNeutralizer.new
                                                                     .call(mutated_source, keep_offset: offset,
                                                                                           keep_lines: line..line,
                                                                                           keep_source: original)
      eval(neutralized, TOPLEVEL_BINDING, path, 1) # rubocop:disable Security/Eval
      print JSON.generate(eval(checks)) # rubocop:disable Security/Eval
    RUBY
  end

  def apply(source, original, mutated, checks)
    Dir.mktmpdir("callback_redeclaration") do |dir|
      path = File.join(dir, "model.rb")
      File.write(path, source)
      out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script, path, original, mutated, checks)
      raise "script failed: #{err}" unless status.success?

      [JSON.parse(out), err]
    end
  end

  it "replaces the validator of a class in a namespace, whose options name the namespace's constants" do
    source = <<~RUBY
      module Shop
        KINDS = [true].freeze

        class Vote
          include ActiveModel::Validations
          attr_accessor :for_lift

          validates :for_lift, inclusion: { in: KINDS }
        end
      end
    RUBY

    result, err = apply(source, "validates :for_lift, inclusion: { in: KINDS }",
                        "validates :for_lift, inclusion: { in: [true, false] }",
                        "vote = Shop::Vote.new; vote.for_lift = false; [vote.valid?, Shop::Vote.validators.size]")

    expect([result, err]).to match([[true, 1], satisfy { |text| !text.include?("could not run") }])
  end

  it "leaves a subclass the validator its parent declares alike when its own registers none" do
    source = <<~RUBY
      class User
        include ActiveModel::Validations
        attr_accessor :email

        validates :email, presence: true
      end

      class Admin < User
        validates(:email, presence: true)
      end
    RUBY

    result, = apply(source, "validates(:email, presence: true)", "validates(:email, presence: false)",
                    "[Admin.new.valid?, Admin.validators.size, User.validators.size]")

    expect(result).to eq([false, 1, 1])
  end
end
