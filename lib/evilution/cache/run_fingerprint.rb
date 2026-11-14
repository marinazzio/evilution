# frozen_string_literal: true

require "digest"
require "json"
require_relative "../cache"
require_relative "../version"
require_relative "spec_digest"

# What a cached verdict depends on beyond the subject and its spec files: the
# settings that decide how a mutation is run and judged, the evilution and
# Ruby versions, the locked gems, and the helpers every spec file loads.
# Settings that only shape the output or the scheduling (format, jobs,
# progress) are left out, so changing them keeps the cache.
class Evilution::Cache::RunFingerprint
  SETTINGS = %i[
    integration isolation profile timeout adaptive_timeout? timeout_factor timeout_floor timeout_ceiling
    baseline example_targeting example_targeting_fallback example_targeting_strategy
    related_specs_heuristic fallback_to_full_suite preload stop_on_kill warmup skip_uncovered?
  ].freeze

  HELPERS = %w[
    .rspec spec/spec_helper.rb spec/rails_helper.rb spec/support test/test_helper.rb test/support
    Gemfile.lock gems.locked
  ].freeze

  def initialize(config, spec_digest: Evilution::Cache::SpecDigest.new)
    @config = config
    @spec_digest = spec_digest
  end

  def to_s
    @to_s ||= Digest::SHA256.hexdigest(JSON.generate(payload))
  end

  private

  def payload
    {
      "evilution" => Evilution::VERSION,
      "ruby" => "#{RUBY_ENGINE} #{RUBY_VERSION}",
      "settings" => SETTINGS.to_h { |name| [name.to_s, @config.public_send(name).to_s] },
      "helpers" => @spec_digest.call(helper_paths).to_s
    }
  end

  def helper_paths
    preload = @config.preload
    preload ? HELPERS + [preload.to_s] : HELPERS
  end
end
