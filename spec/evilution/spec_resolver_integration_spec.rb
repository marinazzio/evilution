# frozen_string_literal: true

require "evilution/spec_resolver"

RSpec.describe Evilution::SpecResolver, "integration" do
  subject(:resolver) { described_class.new }

  context "with Rails project layout" do
    around do |example|
      Dir.chdir(File.join(__dir__, "../support/fixtures/layouts/rails_project")) { example.run }
    end

    describe "controller to request spec" do
      it "resolves controller to request spec" do
        expect(resolver.call("app/controllers/users_controller.rb")).to eq("spec/requests/users_spec.rb")
      end

      it "resolves namespaced controller to request spec" do
        expect(resolver.call("app/controllers/admin/posts_controller.rb")).to eq("spec/requests/admin/posts_spec.rb")
      end
    end

    describe "controller concerns" do
      it "resolves concern without request spec mapping" do
        expect(resolver.call("app/controllers/concerns/authenticatable.rb"))
          .to eq("spec/controllers/concerns/authenticatable_spec.rb")
      end
    end

    describe "model conventions" do
      it "resolves model to model spec" do
        expect(resolver.call("app/models/user.rb")).to eq("spec/models/user_spec.rb")
      end

      it "resolves model concern to concern spec" do
        expect(resolver.call("app/models/concerns/trackable.rb"))
          .to eq("spec/models/concerns/trackable_spec.rb")
      end
    end

    describe "nested model fallback" do
      it "falls back to parent spec when nested spec does not exist" do
        expect(resolver.call("app/models/game/round.rb")).to eq("spec/models/game_spec.rb")
      end
    end

    describe "service conventions" do
      it "resolves service to service spec" do
        expect(resolver.call("app/services/payment/processor.rb"))
          .to eq("spec/services/payment/processor_spec.rb")
      end
    end

    describe "Avo resource conventions" do
      it "resolves Avo resource to resource spec" do
        expect(resolver.call("app/resources/user_resource.rb"))
          .to eq("spec/resources/user_resource_spec.rb")
      end
    end

    describe "resolve_all across conventions" do
      it "resolves multiple source files from different conventions" do
        sources = [
          "app/controllers/users_controller.rb",
          "app/models/user.rb",
          "app/services/payment/processor.rb",
          "app/resources/user_resource.rb"
        ]

        expect(resolver.resolve_all(sources)).to contain_exactly(
          "spec/requests/users_spec.rb",
          "spec/models/user_spec.rb",
          "spec/services/payment/processor_spec.rb",
          "spec/resources/user_resource_spec.rb"
        )
      end

      it "skips source files with no matching spec" do
        sources = [
          "app/models/user.rb",
          "app/models/nonexistent.rb"
        ]

        expect(resolver.resolve_all(sources)).to eq(["spec/models/user_spec.rb"])
      end
    end
  end

  context "with gem project layout" do
    around do |example|
      Dir.chdir(File.join(__dir__, "../support/fixtures/layouts/gem_project")) { example.run }
    end

    describe "lib/ prefix stripping" do
      it "resolves lib file to stripped-prefix spec" do
        expect(resolver.call("lib/evilution/parser.rb")).to eq("spec/evilution/parser_spec.rb")
      end

      it "resolves deeply nested lib file" do
        expect(resolver.call("lib/evilution/ast/node.rb")).to eq("spec/evilution/ast/node_spec.rb")
      end
    end

    describe "lib/ prefix preference" do
      it "prefers stripped-prefix spec over kept-prefix spec" do
        # Both spec/evilution/parser_spec.rb and spec/lib/evilution/parser_spec.rb exist
        expect(resolver.call("lib/evilution/parser.rb")).to eq("spec/evilution/parser_spec.rb")
      end
    end

    describe "fallback within gem layout" do
      it "falls back to parent spec for missing nested spec" do
        # lib/evilution/ast/missing.rb has no direct spec, should fallback to spec/evilution/ast_spec.rb
        # but that doesn't exist either, so try spec/evilution_spec.rb
        # Neither exists, so nil
        expect(resolver.call("lib/evilution/ast/missing.rb")).to be_nil
      end
    end

    describe "resolve_all for gem layout" do
      it "resolves multiple lib files" do
        sources = ["lib/evilution/parser.rb", "lib/evilution/ast/node.rb"]

        expect(resolver.resolve_all(sources)).to contain_exactly(
          "spec/evilution/parser_spec.rb",
          "spec/evilution/ast/node_spec.rb"
        )
      end
    end
  end
end
