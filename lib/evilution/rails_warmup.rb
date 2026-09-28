# frozen_string_literal: true

require_relative "diagnostic"

# Warms Rails state that initialises lazily on a process's first request, once
# in the parent after the preload, so forked mutations inherit it instead of
# each paying the cold start.
#
# Every step is side-effect free. A real request is deliberately NOT used:
# controller callbacks change process-global state -- I18n.locale,
# PaperTrail.request, a session row -- that every fork would then inherit,
# failing unrelated tests and reporting them as kills.
#
# A step whose library is not loaded is skipped silently; a step that raises
# (no application stylesheet, an unusual asset setup) is skipped with a note.
# Warm-up is an optimisation and must never fail or skew the run.
class Evilution::RailsWarmup
  def initialize(application, stream: $stderr)
    @application = application
    @stream = stream
  end

  def call
    step("i18n") { warm_i18n }
    step("routes") { warm_routes }
    step("assets") { warm_assets }
    step("templates") { warm_templates }
  end

  private

  def step(name)
    yield
  rescue StandardError, ScriptError => e
    Evilution::Diagnostic.warn("[evilution] rails warmup: skipped #{name} (#{e.class}: #{e.message})", stream: @stream)
  end

  def warm_i18n
    ::I18n.eager_load! if defined?(::I18n) && ::I18n.respond_to?(:eager_load!)
  end

  # Rails 8 can draw routes lazily; building url_helpers compiles the helpers
  # module every request would otherwise build on first use.
  def warm_routes
    routes = @application.routes
    routes.eager_load! if routes.respond_to?(:eager_load!)
    routes.url_helpers
  end

  def warm_assets
    ::ActionController::Base.helpers.stylesheet_path("application") if defined?(::ActionController::Base)
  end

  # Optional: jhawthorn/actionview_precompiler compiles templates up front.
  def warm_templates
    return unless Gem.loaded_specs.key?("actionview_precompiler")

    require "actionview_precompiler"
    ::ActionviewPrecompiler.precompile
  end
end
