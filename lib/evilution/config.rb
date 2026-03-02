# frozen_string_literal: true

module Evilution
  class Config
    DEFAULTS = {
      jobs: nil,
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

    attr_reader :target_files, :jobs, :timeout, :format, :diff_base,
                :target, :min_score, :integration, :coverage, :verbose, :quiet

    def initialize(**options)
      merged = DEFAULTS.merge(options)
      @target_files = Array(merged[:target_files])
      @jobs = merged[:jobs] || default_jobs
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

    private

    def default_jobs
      require "etc"
      Etc.nprocessors
    end
  end
end
