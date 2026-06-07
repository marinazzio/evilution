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

      it "does not generate a suffix-only fallback candidate for the leaf directory" do
        create_file("spec/models/game/_spec.rb")

        expect(resolver.call("app/models/game/round.rb")).to be_nil
      end
    end

    context "Rails controller to request spec mapping" do
      it "resolves app/controllers/foo_controller.rb to spec/requests/foo_spec.rb" do
        create_file("spec/requests/foo_spec.rb")

        expect(resolver.call("app/controllers/foo_controller.rb")).to eq("spec/requests/foo_spec.rb")
      end

      it "resolves namespaced controller to request spec" do
        create_file("spec/requests/admin/users_spec.rb")

        expect(resolver.call("app/controllers/admin/users_controller.rb")).to eq("spec/requests/admin/users_spec.rb")
      end

      it "prefers request spec over controller spec when both exist" do
        create_file("spec/requests/foo_spec.rb")
        create_file("spec/controllers/foo_controller_spec.rb")

        expect(resolver.call("app/controllers/foo_controller.rb")).to eq("spec/requests/foo_spec.rb")
      end

      it "falls back to controller spec when request spec does not exist" do
        create_file("spec/controllers/foo_controller_spec.rb")

        expect(resolver.call("app/controllers/foo_controller.rb")).to eq("spec/controllers/foo_controller_spec.rb")
      end

      it "resolves deeply namespaced controller to request spec" do
        create_file("spec/requests/api/v1/users_spec.rb")

        expect(resolver.call("app/controllers/api/v1/users_controller.rb")).to eq("spec/requests/api/v1/users_spec.rb")
      end

      it "does not apply request spec mapping to non-controller files" do
        create_file("spec/services/foo_service_spec.rb")

        expect(resolver.call("app/services/foo_service.rb")).to eq("spec/services/foo_service_spec.rb")
      end

      it "does not apply request spec mapping to controller concerns" do
        create_file("spec/controllers/concerns/set_locale_spec.rb")

        expect(resolver.call("app/controllers/concerns/set_locale.rb")).to eq("spec/controllers/concerns/set_locale_spec.rb")
      end

      it "does not map a non-controller-directory file to a request spec even when it ends with _controller" do
        create_file("spec/requests/models/event_spec.rb")

        expect(resolver.call("app/models/event_controller.rb")).to be_nil
      end

      it "does not map a controller-directory file lacking the _controller suffix to a request spec" do
        create_file("spec/requests/foo_spec.rb")

        expect(resolver.call("app/controllers/foo.rb")).to be_nil
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

    # EV-z7f5 / GH #1325: auto-resolution must find specs in the common
    # real-world layouts that do NOT mirror the lib/ path 1:1 — spec/unit,
    # spec/lib with the gem-namespace dir dropped, and basename-only matches.
    context "non-mirrored real-world layouts (EV-z7f5)" do
      it "resolves spec/unit/<basename> (gem-namespace dropped), e.g. webmock" do
        create_file("spec/unit/request_pattern_spec.rb")

        expect(resolver.call("lib/webmock/request_pattern.rb"))
          .to eq("spec/unit/request_pattern_spec.rb")
      end

      it "resolves spec/lib/<namespace-dropped>, e.g. doorkeeper" do
        create_file("spec/lib/oauth/client_spec.rb")

        expect(resolver.call("lib/doorkeeper/oauth/client.rb"))
          .to eq("spec/lib/oauth/client_spec.rb")
      end

      it "drops only the leading gem-namespace dir for nested paths, e.g. concurrent-ruby" do
        create_file("spec/concurrent/utility/processor_counter_spec.rb")

        expect(resolver.call("lib/concurrent-ruby/concurrent/utility/processor_counter.rb"))
          .to eq("spec/concurrent/utility/processor_counter_spec.rb")
      end

      it "prefers the full path mirror over the namespace-dropped match" do
        create_file("spec/webmock/request_pattern_spec.rb")
        create_file("spec/unit/request_pattern_spec.rb")

        expect(resolver.call("lib/webmock/request_pattern.rb"))
          .to eq("spec/webmock/request_pattern_spec.rb")
      end

      it "does not match a basename collision when no convention dir holds it" do
        create_file("spec/unrelated/request_pattern_spec.rb")

        expect(resolver.call("lib/webmock/request_pattern.rb")).to be_nil
      end
    end

    # EV-z7f5 / GH #1325 opt 2: when exact resolution fails, #suggest offers a
    # best-guess candidate by basename glob so the warning can name a file to
    # pass to --spec instead of a bare "use --spec".
    describe "#suggest" do
      it "finds a spec by basename anywhere under the test dir" do
        create_file("spec/unusual/place/bar_spec.rb")

        expect(resolver.suggest("lib/foo/bar.rb")).to eq("spec/unusual/place/bar_spec.rb")
      end

      it "matches a substring basename (partial name)" do
        create_file("spec/weird/my_bar_thing_spec.rb")

        expect(resolver.suggest("lib/foo/my_bar_thing.rb")).to eq("spec/weird/my_bar_thing_spec.rb")
      end

      it "prefers the shallowest candidate when several match" do
        create_file("spec/bar_spec.rb")
        create_file("spec/a/b/bar_spec.rb")

        expect(resolver.suggest("lib/foo/bar.rb")).to eq("spec/bar_spec.rb")
      end

      it "returns nil when nothing resembles the basename" do
        create_file("spec/unrelated_spec.rb")

        expect(resolver.suggest("lib/foo/bar.rb")).to be_nil
      end

      it "returns nil for blank input" do
        expect(resolver.suggest(nil)).to be_nil
        expect(resolver.suggest("")).to be_nil
      end

      context "with the minitest suffix" do
        subject(:resolver) { described_class.new(test_dir: "test", test_suffix: "_test.rb") }

        it "suggests the test_<name>.rb prefix convention" do
          create_file("test/test_connection_pool.rb")

          expect(resolver.suggest("lib/connection_pool.rb")).to eq("test/test_connection_pool.rb")
        end
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

    context "Minitest layout (test/ directory, _test.rb suffix)" do
      subject(:resolver) { described_class.new(test_dir: "test", test_suffix: "_test.rb", request_dir: "integration") }

      it "resolves lib/foo/bar.rb to test/foo/bar_test.rb" do
        create_file("test/foo/bar_test.rb")

        expect(resolver.call("lib/foo/bar.rb")).to eq("test/foo/bar_test.rb")
      end

      it "resolves app/models/user.rb to test/models/user_test.rb" do
        create_file("test/models/user_test.rb")

        expect(resolver.call("app/models/user.rb")).to eq("test/models/user_test.rb")
      end

      it "resolves with kept prefix fallback" do
        create_file("test/lib/foo/bar_test.rb")

        expect(resolver.call("lib/foo/bar.rb")).to eq("test/lib/foo/bar_test.rb")
      end

      it "resolves controller to integration test" do
        create_file("test/integration/users_test.rb")

        expect(resolver.call("app/controllers/users_controller.rb")).to eq("test/integration/users_test.rb")
      end

      it "falls back to parent test when nested test does not exist" do
        create_file("test/models/game_test.rb")

        expect(resolver.call("app/models/game/round.rb")).to eq("test/models/game_test.rb")
      end

      it "returns nil when no test file exists" do
        expect(resolver.call("lib/foo/bar.rb")).to be_nil
      end

      it "resolves other prefixes under test/" do
        create_file("test/src/foo_test.rb")

        expect(resolver.call("src/foo.rb")).to eq("test/src/foo_test.rb")
      end

      # EV-z7f5 / GH #1325: Test::Unit/minitest gems commonly use a `test_`
      # filename PREFIX (test_foo.rb) and a test/unit/ root rather than a
      # mirrored `_test.rb` suffix.
      it "resolves the test_<name>.rb prefix convention, e.g. connection_pool" do
        create_file("test/test_connection_pool.rb")

        expect(resolver.call("lib/connection_pool.rb")).to eq("test/test_connection_pool.rb")
      end

      it "resolves test/unit/<basename> layout" do
        create_file("test/unit/bar_test.rb")

        expect(resolver.call("lib/foo/bar.rb")).to eq("test/unit/bar_test.rb")
      end
    end

    context "with spec_pattern filter" do
      it "filters candidates by glob before existence check" do
        create_file("spec/requests/foo_spec.rb")
        create_file("spec/controllers/foo_controller_spec.rb")

        result = resolver.call("app/controllers/foo_controller.rb",
                               spec_pattern: "spec/controllers/**/*_spec.rb")

        expect(result).to eq("spec/controllers/foo_controller_spec.rb")
      end

      it "returns nil when glob excludes all candidates" do
        create_file("spec/foo_spec.rb")

        result = resolver.call("lib/foo.rb", spec_pattern: "spec/requests/**/*_spec.rb")

        expect(result).to be_nil
      end

      it "behaves as default when spec_pattern is nil" do
        create_file("spec/foo_spec.rb")

        expect(resolver.call("lib/foo.rb", spec_pattern: nil)).to eq("spec/foo_spec.rb")
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

  # Regression coverage for EV-vlbh / GH #1191: SpecResolver gained a
  # PROJECT_ROOT fallback used by isolators chdir'd into a per-mutation
  # sandbox. The fallback is gated on Evilution.in_isolated_worker? so an
  # unflagged caller never silently resolves against the dev tree. These
  # specs pin both directions of the flag.
  describe "isolated-worker fallback" do
    around do |example|
      previous = Evilution.instance_variable_get(:@in_isolated_worker)
      example.run
    ensure
      Evilution.instance_variable_set(:@in_isolated_worker, previous)
    end

    # Kills conditional_negation on spec_resolver.rb:34
    # (`unless Evilution.in_isolated_worker?` -> `unless true`). With the
    # mutated guard, project_relative_exists? falls through to a
    # PROJECT_ROOT lookup even when the flag is unset, silently leaking
    # the dev tree into unrelated callers.
    it "returns nil for a CWD-missing spec when the flag is unset (no PROJECT_ROOT fallback)" do
      probe = "spec/evilution/spec_resolver_spec.rb"
      skip "PROJECT_ROOT probe missing" unless File.exist?(File.join(Evilution::PROJECT_ROOT, probe))

      # CWD is the per-example mktmpdir; the probe exists at PROJECT_ROOT
      # but NOT under CWD. With the flag unset, resolution must stop at CWD.
      expect(resolver.call("lib/evilution/spec_resolver.rb")).to be_nil
    end

    it "resolves via PROJECT_ROOT when the flag is set and the CWD lookup fails" do
      probe_source = "lib/evilution/spec_resolver.rb"
      probe_spec = "spec/evilution/spec_resolver_spec.rb"
      skip "PROJECT_ROOT probe missing" unless File.exist?(File.join(Evilution::PROJECT_ROOT, probe_spec))

      Evilution.in_isolated_worker!

      expect(resolver.call(probe_source)).to eq(probe_spec)
    end

    # Kills conditional_negation on spec_resolver.rb:47 (the
    # `if Evilution.in_isolated_worker?` guard on the PROJECT_ROOT prefix
    # strip). With the flag unset the prefix must be left in place — the
    # mutated `if true` would silently strip it for any caller.
    it "does not strip the PROJECT_ROOT prefix from absolute source paths when the flag is unset" do
      # SpecResolver builds candidates as `"#{test_dir}/#{normalized_source}"`,
      # so when the absolute source is left intact the candidate keeps the
      # leading slash, producing a double-slash join. Both candidates are
      # created on disk; the resolver picks whichever the (un)stripped path
      # produces.
      absolute_source = "#{Evilution::PROJECT_ROOT}/lib/x.rb"
      raw_candidate = "spec/#{absolute_source.sub(/\.rb\z/, "_spec.rb")}"
      stripped_candidate = "spec/lib/x_spec.rb"
      create_file(raw_candidate)
      create_file(stripped_candidate)

      expect(resolver.call(absolute_source)).to eq(raw_candidate)
    end

    it "strips the PROJECT_ROOT prefix from absolute source paths when the flag is set" do
      Evilution.in_isolated_worker!
      absolute_source = "#{Evilution::PROJECT_ROOT}/lib/x.rb"
      raw_candidate = "spec/#{absolute_source.sub(/\.rb\z/, "_spec.rb")}"
      stripped_candidate = "spec/lib/x_spec.rb"
      create_file(raw_candidate)
      create_file(stripped_candidate)

      expect(resolver.call(absolute_source)).to eq(stripped_candidate)
    end
  end
end
