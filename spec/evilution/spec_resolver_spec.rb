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

  def create_file(path, content = "")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
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

    # When a nested source has no 1:1 spec, the specs living in the source's own
    # mirror directory are a better bet than the parent directory's spec: they
    # are ranked by evidence that they exercise the subject.
    context "sibling specs in the subject's own mirror directory" do
      def build_timeline_layout
        create_file("app/models/game_breakdown/timeline/night_warnings.rb",
                    "class GameBreakdown::Timeline::NightWarnings; end\n")
        create_file("app/models/game_breakdown/timeline/warnings.rb",
                    "class GameBreakdown::Timeline::Warnings\n  def call = NightWarnings.new.call\nend\n")
        create_file("spec/models/game_breakdown/timeline_spec.rb",
                    "RSpec.describe GameBreakdown::Timeline do\nend\n")
        create_file("spec/models/game_breakdown/timeline/warnings_spec.rb",
                    "RSpec.describe GameBreakdown::Timeline::Warnings do\n  it { expect(night).to be_empty }\nend\n")
      end

      it "prefers a sibling spec whose subject calls the source over the parent directory's spec" do
        build_timeline_layout

        expect(resolver.call("app/models/game_breakdown/timeline/night_warnings.rb"))
          .to eq("spec/models/game_breakdown/timeline/warnings_spec.rb")
      end

      it "prefers a sibling spec that mentions the subject constant over the parent directory's spec" do
        create_file("spec/models/game_spec.rb", "RSpec.describe Game do\nend\n")
        create_file("spec/models/game/scoring_spec.rb",
                    "RSpec.describe Game::Scoring do\n  let(:round) { Game::Round.new }\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to eq("spec/models/game/scoring_spec.rb")
      end

      it "still falls back to the parent directory's spec when no sibling spec relates to the subject" do
        create_file("spec/models/game_spec.rb", "RSpec.describe Game do\nend\n")
        create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to eq("spec/models/game_spec.rb")
      end

      it "prefers the 1:1 mirror spec over a related sibling spec" do
        build_timeline_layout
        create_file("spec/models/game_breakdown/timeline/night_warnings_spec.rb")

        expect(resolver.call("app/models/game_breakdown/timeline/night_warnings.rb"))
          .to eq("spec/models/game_breakdown/timeline/night_warnings_spec.rb")
      end

      it "does not treat a longer constant that merely starts with the subject name as a mention" do
        create_file("spec/models/game_spec.rb", "RSpec.describe Game do\nend\n")
        create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\n  RoundHelper\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to eq("spec/models/game_spec.rb")
      end

      it "does not treat a snake_case mention of the subject as a constant mention" do
        create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\n  round\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to be_nil
      end

      it "matches an acronym constant regardless of its capitalisation" do
        create_file("spec/services/export/report_spec.rb",
                    "RSpec.describe Export::Report do\n  HTMLRenderer.new\nend\n")

        expect(resolver.call("app/services/export/html_renderer.rb"))
          .to eq("spec/services/export/report_spec.rb")
      end

      it "only scans the subject's own mirror directory, not deeper subdirectories" do
        create_file("spec/models/game/round/deep_spec.rb", "RSpec.describe Game::Round do\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to be_nil
      end

      it "does not scan the test root for a top-level source" do
        create_file("spec/other_spec.rb", "RSpec.describe Other do\n  Foo.new\nend\n")

        expect(resolver.call("lib/foo.rb")).to be_nil
      end

      it "honours spec_pattern for sibling specs" do
        build_timeline_layout

        result = resolver.call("app/models/game_breakdown/timeline/night_warnings.rb",
                               spec_pattern: "spec/models/game_breakdown/*_spec.rb")

        expect(result).to eq("spec/models/game_breakdown/timeline_spec.rb")
      end

      it "finds sibling specs in a namespace-dropped mirror directory" do
        create_file("lib/acme/billing/invoice.rb", "class Acme::Billing::Invoice; end\n")
        create_file("spec/billing/ledger_spec.rb", "RSpec.describe Billing::Ledger do\n  Invoice.new\nend\n")

        expect(resolver.call("lib/acme/billing/invoice.rb")).to eq("spec/billing/ledger_spec.rb")
      end

      # One level below app/ the mirror directory is a whole test root
      # (spec/models), so every model spec mentioning the subject would match.
      it "does not scan the mirror directory of a source one level below app/" do
        create_file("app/models/user.rb", "class User; end\n")
        create_file("spec/models/account_spec.rb",
                    "RSpec.describe Account do\n  it \"belongs to a User\" do\n    User.new\n  end\nend\n")

        expect(resolver.call("app/models/user.rb")).to be_nil
      end

      it "does not scan the gem namespace directory for a source one level below lib/<gem>/" do
        create_file("spec/acme/ledger_spec.rb", "RSpec.describe Acme::Ledger do\n  Acme::Invoice.new\nend\n")

        expect(resolver.call("lib/acme/invoice.rb")).to be_nil
      end

      it "ignores a subject name that appears only in a comment" do
        create_file("spec/models/game/zebra_spec.rb", "RSpec.describe Game::Zebra do\n  # Round handling\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to be_nil
      end

      it "ignores a subject name that appears only in a string" do
        create_file("spec/models/game/zebra_spec.rb",
                    "RSpec.describe Game::Zebra do\n  it \"belongs to a Round\" do\n  end\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to be_nil
      end

      it "ignores a sibling whose mirrored source names the subject only in a comment" do
        create_file("app/models/game/scoring.rb", "# Round scores are kept elsewhere\nclass Game::Scoring; end\n")
        create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to be_nil
      end

      it "does not read sibling specs that spec_pattern excludes" do
        build_timeline_layout
        allow(Evilution::SpecResolver::ProjectFiles).to receive(:read).and_call_original

        resolver.call("app/models/game_breakdown/timeline/night_warnings.rb",
                      spec_pattern: "spec/models/game_breakdown/*_spec.rb")

        expect(Evilution::SpecResolver::ProjectFiles).not_to have_received(:read)
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

    # auto-resolution must find specs in the common
    # real-world layouts that do NOT mirror the lib/ path 1:1 — spec/unit,
    # spec/lib with the gem-namespace dir dropped, and basename-only matches.
    context "non-mirrored real-world layouts" do
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

    # when exact resolution fails, #suggest offers a
    # best-guess candidate by basename glob so the warning can name a file to
    # pass to --spec instead of a bare "use --spec".
    describe "#suggest" do
      it "finds a spec by basename anywhere under the test dir" do
        create_file("spec/unusual/place/bar_spec.rb")

        expect(resolver.suggest("lib/foo/bar.rb")).to eq("spec/unusual/place/bar_spec.rb")
      end

      it "matches when the source basename is a substring of the spec filename" do
        create_file("spec/weird/my_bar_thing_spec.rb")

        # source basename "bar" is a substring of "my_bar_thing"
        expect(resolver.suggest("lib/foo/bar.rb")).to eq("spec/weird/my_bar_thing_spec.rb")
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

      it "prefers a sibling test in the subject's own mirror directory over the parent directory's test" do
        create_file("test/models/game_test.rb", "class GameTest < Minitest::Test; end\n")
        create_file("test/models/game/scoring_test.rb",
                    "class Game::ScoringTest < Minitest::Test\n  def test_round = Game::Round.new\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to eq("test/models/game/scoring_test.rb")
      end

      it "ranks a sibling test named after the subject above a caller test" do
        create_file("app/models/game/scoring.rb", "class Game::Scoring\n  def call = Round.new\nend\n")
        create_file("test/models/game/scoring_test.rb", "class Game::ScoringTest < Minitest::Test; end\n")
        create_file("test/models/game/test_round.rb",
                    "class TestRound < Minitest::Test\n  def test_it = Game::Round.new\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to eq("test/models/game/test_round.rb")
      end

      it "considers test_-prefixed sibling tests" do
        create_file("test/models/game_test.rb", "class GameTest < Minitest::Test; end\n")
        create_file("test/models/game/test_scoring.rb",
                    "class TestScoring < Minitest::Test\n  def test_round = Game::Round.new\nend\n")

        expect(resolver.call("app/models/game/round.rb")).to eq("test/models/game/test_scoring.rb")
      end

      it "resolves other prefixes under test/" do
        create_file("test/src/foo_test.rb")

        expect(resolver.call("src/foo.rb")).to eq("test/src/foo_test.rb")
      end

      # Test::Unit/minitest gems commonly use a `test_`
      # filename PREFIX (test_foo.rb) and a test/unit/ root rather than a
      # mirrored `_test.rb` suffix.
      it "resolves the test_<name>.rb prefix convention, e.g. connection_pool" do
        create_file("test/test_connection_pool.rb")

        expect(resolver.call("lib/connection_pool.rb")).to eq("test/test_connection_pool.rb")
      end

      # nested sources whose tests use a FLAT, namespace-
      # prefixed filename — the lib-relative path flattened with underscores and
      # given a `test_` prefix (test/test_connection_pool_timed_stack.rb), with
      # no test/connection_pool/ subdir. Real case: mperham/connection_pool.
      it "resolves the flat namespace-prefixed convention, e.g. connection_pool/timed_stack" do
        create_file("test/test_connection_pool_timed_stack.rb")

        expect(resolver.call("lib/connection_pool/timed_stack.rb"))
          .to eq("test/test_connection_pool_timed_stack.rb")
      end

      it "flattens deeper namespaces into the prefixed name" do
        create_file("test/test_a_b_c.rb")

        expect(resolver.call("lib/a/b/c.rb")).to eq("test/test_a_b_c.rb")
      end

      it "ranks the mirrored layout above the flat prefixed name when both exist" do
        create_file("test/connection_pool/timed_stack_test.rb")
        create_file("test/test_connection_pool_timed_stack.rb")

        expect(resolver.call("lib/connection_pool/timed_stack.rb"))
          .to eq("test/connection_pool/timed_stack_test.rb")
      end

      # The flat form is built from the FULL lib-relative path only — not from
      # namespace-dropped variants — so a namespaced source must NOT resolve to
      # a basename-flattened name that drops leading segments (collision guard).
      it "does not flatten namespace-dropped variants into the prefixed name" do
        create_file("test/test_y_z.rb")

        expect(resolver.call("lib/x/y/z.rb")).to be_nil
      end

      # A naming convention names the subject exactly; a sibling that mentions
      # it is only fuzzy evidence.
      it "prefers the flat namespace-prefixed test over a sibling test that mentions the subject" do
        create_file("test/test_acme_pool_timed_stack.rb")
        create_file("test/acme/pool/wrapper_test.rb",
                    "class WrapperTest < Minitest::Test\n  def test_it = Acme::Pool::TimedStack.new\nend\n")

        expect(resolver.call("lib/acme/pool/timed_stack.rb")).to eq("test/test_acme_pool_timed_stack.rb")
      end

      it "prefers the test_<name>.rb prefix convention over a sibling test that mentions the subject" do
        create_file("test/test_timed_stack.rb")
        create_file("test/acme/pool/wrapper_test.rb",
                    "class WrapperTest < Minitest::Test\n  def test_it = Acme::Pool::TimedStack.new\nend\n")

        expect(resolver.call("lib/acme/pool/timed_stack.rb")).to eq("test/test_timed_stack.rb")
      end

      it "prefers a naming-convention test over the parent directory's test" do
        create_file("test/acme/pool_test.rb")
        create_file("test/test_acme_pool_timed_stack.rb")

        expect(resolver.call("lib/acme/pool/timed_stack.rb")).to eq("test/test_acme_pool_timed_stack.rb")
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

    # Kills conditional_negation on the ProjectFiles.exist? guard
    # (`unless Evilution.in_isolated_worker?` -> `unless true`). With the
    # mutated guard, the existence check falls through to a
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

    # #suggest must honour the same PROJECT_ROOT contract as #call: when an
    # isolated worker is chdir'd into a sandbox, glob against PROJECT_ROOT so
    # the best-guess hint still finds real project files.
    it "globs PROJECT_ROOT for suggestions when the flag is set and CWD is empty" do
      probe_spec = "spec/evilution/spec_resolver_spec.rb"
      skip "PROJECT_ROOT probe missing" unless File.exist?(File.join(Evilution::PROJECT_ROOT, probe_spec))

      Evilution.in_isolated_worker!

      # CWD is the per-example mktmpdir (no spec files); the match lives at
      # PROJECT_ROOT and is only reachable via the base: PROJECT_ROOT glob.
      expect(resolver.suggest("lib/evilution/spec_resolver.rb")).to eq(probe_spec)
    end

    it "finds no suggestion against an empty CWD when the flag is unset" do
      expect(resolver.suggest("lib/evilution/spec_resolver.rb")).to be_nil
    end

    # The sibling ranking lists, reads and follows mirrored sources through the
    # same PROJECT_ROOT fallback; the CWD here is an empty sandbox.
    it "ranks sibling specs that live under PROJECT_ROOT when the flag is set" do
      Dir.mktmpdir do |root|
        Dir.chdir(root) do
          create_file("app/models/game/scoring.rb", "class Game::Scoring\n  def call = Round.new\nend\n")
          create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")
        end
        stub_const("Evilution::PROJECT_ROOT", root)
        Evilution.in_isolated_worker!

        expect(resolver.call("app/models/game/round.rb")).to eq("spec/models/game/scoring_spec.rb")
      end
    end
  end

  describe "#resolve_specs" do
    it "returns the mirror spec file as a single-element array when it exists" do
      create_file("spec/foo/bar_spec.rb")

      expect(resolver.resolve_specs("lib/foo/bar.rb")).to eq(["spec/foo/bar_spec.rb"])
    end

    it "returns nil when neither a mirror file nor a grouped directory exists" do
      expect(resolver.resolve_specs("lib/foo/bar.rb")).to be_nil
    end

    context "sibling specs in the subject's own mirror directory" do
      it "returns every related sibling spec, ranked: describes the subject, then callers, then mentions" do
        create_file("app/models/game/round.rb", "class Game::Round; end\n")
        create_file("app/models/game/scoring.rb", "class Game::Scoring\n  def call = Round.new\nend\n")
        create_file("spec/models/game_spec.rb", "RSpec.describe Game do\nend\n")
        create_file("spec/models/game/a_mentions_spec.rb", "RSpec.describe Game::A do\n  Game::Round\nend\n")
        create_file("spec/models/game/scoring_spec.rb", "RSpec.describe Game::Scoring do\nend\n")
        create_file("spec/models/game/round_behaviour_spec.rb", "RSpec.describe Game::Round, :slow do\nend\n")
        create_file("spec/models/game/unrelated_spec.rb", "RSpec.describe Game::Unrelated do\nend\n")

        expect(resolver.resolve_specs("app/models/game/round.rb")).to eq(
          [
            "spec/models/game/round_behaviour_spec.rb",
            "spec/models/game/scoring_spec.rb",
            "spec/models/game/a_mentions_spec.rb"
          ]
        )
      end

      it "returns the parent directory's spec when no sibling relates to the subject" do
        create_file("spec/models/game_spec.rb", "RSpec.describe Game do\nend\n")
        create_file("spec/models/game/unrelated_spec.rb", "RSpec.describe Game::Unrelated do\nend\n")

        expect(resolver.resolve_specs("app/models/game/round.rb")).to eq(["spec/models/game_spec.rb"])
      end

      it "honours spec_pattern when returning sibling specs" do
        create_file("spec/models/game/a_spec.rb", "RSpec.describe Game::A do\n  Game::Round\nend\n")
        create_file("spec/models/game/b_spec.rb", "RSpec.describe Game::B do\n  Game::Round\nend\n")

        expect(resolver.resolve_specs("app/models/game/round.rb", spec_pattern: "**/b_spec.rb"))
          .to eq(["spec/models/game/b_spec.rb"])
      end
    end

    context "dir-grouped layout (minitest)" do
      subject(:resolver) { described_class.new(test_dir: "test", test_suffix: "_test.rb") }

      it "expands a test/unit/<class>/ directory of *_test.rb files into the file list" do
        create_file("test/unit/branch/branch_test.rb")
        create_file("test/unit/branch/branch_with_conflict_test.rb")

        expect(resolver.resolve_specs("lib/state_machines/branch.rb")).to contain_exactly(
          "test/unit/branch/branch_test.rb",
          "test/unit/branch/branch_with_conflict_test.rb"
        )
      end

      it "finds test files nested deeper inside the grouped directory" do
        create_file("test/unit/branch/sub/nested_test.rb")

        expect(resolver.resolve_specs("lib/state_machines/branch.rb")).to eq(
          ["test/unit/branch/sub/nested_test.rb"]
        )
      end

      it "also matches the test_ prefix convention inside the grouped directory" do
        create_file("test/unit/branch/test_branch.rb")

        expect(resolver.resolve_specs("lib/state_machines/branch.rb")).to eq(
          ["test/unit/branch/test_branch.rb"]
        )
      end

      it "prefers a mirror test file over a same-named grouped directory" do
        create_file("test/unit/branch_test.rb")
        create_file("test/unit/branch/branch_test.rb")

        expect(resolver.resolve_specs("lib/state_machines/branch.rb")).to eq(
          ["test/unit/branch_test.rb"]
        )
      end

      # A grouped directory is dedicated to the subject; a sibling or a parent
      # test is not.
      it "prefers the grouped directory over a sibling test that mentions the subject" do
        create_file("test/unit/acme/x/branch/a_test.rb")
        create_file("test/unit/acme/x/other_test.rb",
                    "class OtherTest < Minitest::Test\n  def test_it = Branch.new\nend\n")

        expect(resolver.resolve_specs("lib/acme/x/branch.rb")).to eq(["test/unit/acme/x/branch/a_test.rb"])
      end

      it "prefers the grouped directory over the parent directory's test" do
        create_file("test/unit/acme/x/branch/a_test.rb")
        create_file("test/acme/x_test.rb")

        expect(resolver.resolve_specs("lib/acme/x/branch.rb")).to eq(["test/unit/acme/x/branch/a_test.rb"])
      end

      it "prefers a naming-convention test over the grouped directory" do
        create_file("test/unit/acme/x/branch/a_test.rb")
        create_file("test/test_acme_x_branch.rb")

        expect(resolver.resolve_specs("lib/acme/x/branch.rb")).to eq(["test/test_acme_x_branch.rb"])
      end

      it "honours spec_pattern when expanding a grouped directory" do
        create_file("test/unit/branch/branch_test.rb")
        create_file("test/unit/branch/skip_test.rb")

        expect(
          resolver.resolve_specs("lib/state_machines/branch.rb", spec_pattern: "**/branch_test.rb")
        ).to eq(["test/unit/branch/branch_test.rb"])
      end
    end
  end
end
