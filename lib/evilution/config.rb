# frozen_string_literal: true

require "yaml"

module Evilution
  class Config
    CONFIG_FILES = %w[.evilution.yml config/evilution.yml].freeze

    DEFAULTS = {
      timeout: 10,
      format: :text,
      diff_base: nil,
      target: nil,
      min_score: 0.0,
      integration: :rspec,
      coverage: true,
      verbose: false,
      quiet: false
    }.freeze

    attr_reader :target_files, :timeout, :format, :diff_base,
                :target, :min_score, :integration, :coverage, :verbose, :quiet

    def initialize(**options)
      file_options = options.delete(:skip_config_file) ? {} : load_config_file
      merged = DEFAULTS.merge(file_options).merge(options)
      @target_files = Array(merged[:target_files])
      @timeout = merged[:timeout]
      @format = merged[:format].to_sym
      @diff_base = merged[:diff_base]
      @target = merged[:target]
      @min_score = merged[:min_score].to_f
      @integration = merged[:integration].to_sym
      @coverage = merged[:coverage]
      @verbose = merged[:verbose]
      @quiet = merged[:quiet]
      freeze
    end

    def json?
      format == :json
    end

    def text?
      format == :text
    end

    def diff?
      !diff_base.nil?
    end

    # Generates a default config file template.
    def self.default_template
      <<~YAML
        # Evilution configuration
        # See: https://github.com/marinazzio/evilution

        # Per-mutation timeout in seconds (default: 10)
        # timeout: 10

        # Output format: text or json (default: text)
        # format: text

        # Minimum mutation score to pass (0.0 to 1.0, default: 0.0)
        # min_score: 0.0

        # Test integration: rspec (default: rspec)
        # integration: rspec

        # Skip mutations on uncovered lines (default: true)
        # coverage: true
      YAML
    end

    private

    def load_config_file
      CONFIG_FILES.each do |path|
        next unless File.exist?(path)

        data = YAML.safe_load_file(path, symbolize_names: true)
        return data.is_a?(Hash) ? data : {}
      end

      {}
    end
  end
end
