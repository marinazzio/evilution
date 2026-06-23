# frozen_string_literal: true

require "spec_helper"
require "evilution/integration/rspec/unresolved_spec_warner"

RSpec.describe Evilution::Integration::RSpec::UnresolvedSpecWarner do
  let(:warner) { described_class.new }

  it "warns on first call for a file_path" do
    expect { warner.call("lib/foo.rb", fallback_to_full_suite: false) }
      .to output(%r{No matching spec found for lib/foo\.rb, marking mutation unresolved}).to_stderr
  end

  it "is silent on subsequent calls for the same file_path" do
    warner.call("lib/foo.rb", fallback_to_full_suite: false)
    expect { warner.call("lib/foo.rb", fallback_to_full_suite: false) }.not_to output.to_stderr
  end

  it "warns again for a different file_path" do
    warner.call("lib/foo.rb", fallback_to_full_suite: false)
    expect { warner.call("lib/bar.rb", fallback_to_full_suite: false) }.to output(%r{lib/bar\.rb}).to_stderr
  end

  it "uses 'running full suite' message when fallback flag is true" do
    expect { warner.call("lib/foo.rb", fallback_to_full_suite: true) }
      .to output(/running full suite/).to_stderr
  end

  it "uses 'marking mutation unresolved' message when fallback flag is false" do
    expect { warner.call("lib/foo.rb", fallback_to_full_suite: false) }
      .to output(/marking mutation unresolved/).to_stderr
  end

  # EV-ajby / GH #1376: behaviour-named layouts (e.g. aasm's lib/aasm/base.rb,
  # whose specs are named by behaviour, not by lib path) resolve to nothing.
  # The honest signal stays :unresolved, but the warning must name BOTH escape
  # hatches so the user can recover a score without guessing.
  it "suggests --fallback-full-suite when marking unresolved" do
    expect { warner.call("lib/foo.rb", fallback_to_full_suite: false) }
      .to output(/--fallback-full-suite/).to_stderr
  end

  it "does not suggest --fallback-full-suite when already running full suite" do
    expect { warner.call("lib/foo.rb", fallback_to_full_suite: true) }
      .not_to output(/--fallback-full-suite/).to_stderr
  end
end
