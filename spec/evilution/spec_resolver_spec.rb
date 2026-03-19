# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/spec_resolver"

RSpec.describe Evilution::SpecResolver do
  subject(:resolver) { described_class.new }

  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def create_file(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
  end

  describe "#call" do
    context "gem layout (lib/ prefix)" do
      it "resolves lib/foo/bar.rb to spec/foo/bar_spec.rb" do
        create_file("spec/foo/bar_spec.rb")

        expect(resolver.call("lib/foo/bar.rb")).to eq("spec/foo/bar_spec.rb")
      end

      it "resolves lib/foo/bar.rb to spec/lib/foo/bar_spec.rb when lib-prefixed spec exists" do
        create_file("spec/lib/foo/bar_spec.rb")

        expect(resolver.call("lib/foo/bar.rb")).to eq("spec/lib/foo/bar_spec.rb")
      end

      it "prefers spec/foo/bar_spec.rb over spec/lib/foo/bar_spec.rb when both exist" do
        create_file("spec/foo/bar_spec.rb")
        create_file("spec/lib/foo/bar_spec.rb")

        expect(resolver.call("lib/foo/bar.rb")).to eq("spec/foo/bar_spec.rb")
      end

      it "resolves deeply nested paths" do
        create_file("spec/a/b/c/d_spec.rb")

        expect(resolver.call("lib/a/b/c/d.rb")).to eq("spec/a/b/c/d_spec.rb")
      end

      it "resolves top-level lib file" do
        create_file("spec/foo_spec.rb")

        expect(resolver.call("lib/foo.rb")).to eq("spec/foo_spec.rb")
      end
    end

    context "Rails layout (app/ prefix)" do
      it "resolves app/models/user.rb to spec/models/user_spec.rb" do
        create_file("spec/models/user_spec.rb")

        expect(resolver.call("app/models/user.rb")).to eq("spec/models/user_spec.rb")
      end

      it "resolves app/controllers/users_controller.rb" do
        create_file("spec/controllers/users_controller_spec.rb")

        expect(resolver.call("app/controllers/users_controller.rb")).to eq("spec/controllers/users_controller_spec.rb")
      end

      it "resolves app/services/payment/processor.rb" do
        create_file("spec/services/payment/processor_spec.rb")

        expect(resolver.call("app/services/payment/processor.rb")).to eq("spec/services/payment/processor_spec.rb")
      end
    end

    context "other prefixes" do
      it "resolves src/foo.rb to spec/src/foo_spec.rb" do
        create_file("spec/src/foo_spec.rb")

        expect(resolver.call("src/foo.rb")).to eq("spec/src/foo_spec.rb")
      end

      it "resolves root-level file to spec/foo_spec.rb" do
        create_file("spec/foo_spec.rb")

        expect(resolver.call("foo.rb")).to eq("spec/foo_spec.rb")
      end
    end

    context "nested module fallback" do
      it "falls back to parent spec when nested spec does not exist" do
        create_file("spec/models/game_spec.rb")

        expect(resolver.call("app/models/game/round.rb")).to eq("spec/models/game_spec.rb")
      end

      it "prefers exact match over parent fallback" do
        create_file("spec/models/game/round_spec.rb")
        create_file("spec/models/game_spec.rb")

        expect(resolver.call("app/models/game/round.rb")).to eq("spec/models/game/round_spec.rb")
      end

      it "falls back to parent spec for deeply nested paths" do
        create_file("spec/services/payment_spec.rb")

        expect(resolver.call("app/services/payment/stripe/charge.rb")).to eq("spec/services/payment_spec.rb")
      end

      it "falls back through multiple parent levels" do
        create_file("spec/foo_spec.rb")

        expect(resolver.call("lib/foo/bar/baz.rb")).to eq("spec/foo_spec.rb")
      end

      it "falls back for two-segment paths" do
        create_file("spec/foo_spec.rb")

        expect(resolver.call("lib/foo/bar.rb")).to eq("spec/foo_spec.rb")
      end

      it "falls back using kept prefix layout" do
        create_file("spec/lib/foo_spec.rb")

        expect(resolver.call("lib/foo/bar/baz.rb")).to eq("spec/lib/foo_spec.rb")
      end

      it "does not fall back to spec directory root" do
        expect(resolver.call("lib/foo/bar/baz.rb")).to be_nil
      end
    end

    context "Rails concerns" do
      it "resolves app/models/concerns/trackable.rb to spec/models/concerns/trackable_spec.rb" do
        create_file("spec/models/concerns/trackable_spec.rb")

        expect(resolver.call("app/models/concerns/trackable.rb")).to eq("spec/models/concerns/trackable_spec.rb")
      end
    end

    context "no matching spec" do
      it "returns nil when no spec file exists" do
        expect(resolver.call("lib/foo/bar.rb")).to be_nil
      end

      it "returns nil when spec directory does not exist" do
        expect(resolver.call("lib/foo.rb")).to be_nil
      end
    end

    context "path normalization" do
      it "strips leading ./ from paths" do
        create_file("spec/foo/bar_spec.rb")

        expect(resolver.call("./lib/foo/bar.rb")).to eq("spec/foo/bar_spec.rb")
      end

      it "handles absolute paths by making them relative to pwd" do
        create_file("spec/foo/bar_spec.rb")

        expect(resolver.call("#{Dir.pwd}/lib/foo/bar.rb")).to eq("spec/foo/bar_spec.rb")
      end
    end

    context "invalid input" do
      it "returns nil for nil input" do
        expect(resolver.call(nil)).to be_nil
      end

      it "returns nil for empty string" do
        expect(resolver.call("")).to be_nil
      end
    end

    context "multiple source files" do
      it "resolves each file independently via #resolve_all" do
        create_file("spec/foo/bar_spec.rb")
        create_file("spec/models/user_spec.rb")

        results = resolver.resolve_all(["lib/foo/bar.rb", "app/models/user.rb", "lib/missing.rb"])

        expect(results).to eq(["spec/foo/bar_spec.rb", "spec/models/user_spec.rb"])
      end

      it "returns empty array when no specs found" do
        results = resolver.resolve_all(["lib/missing.rb"])

        expect(results).to eq([])
      end

      it "deduplicates resolved spec files" do
        create_file("spec/foo_spec.rb")

        results = resolver.resolve_all(["lib/foo.rb", "lib/foo.rb"])

        expect(results).to eq(["spec/foo_spec.rb"])
      end

      it "returns empty array for nil input" do
        expect(resolver.resolve_all(nil)).to eq([])
      end
    end
  end
end
