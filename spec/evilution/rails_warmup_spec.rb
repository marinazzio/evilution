# frozen_string_literal: true

require "stringio"
require "evilution/rails_warmup"

RSpec.describe Evilution::RailsWarmup do
  let(:stream) { StringIO.new }
  let(:url_helpers) { Module.new }
  let(:routes) { double("RouteSet", url_helpers: url_helpers) }
  let(:app) { double("Application", routes: routes) }

  def warm_up
    described_class.new(app, stream: stream).call
  end

  it "eager-loads the I18n backend" do
    i18n = stub_const("I18n", Module.new)
    allow(i18n).to receive(:eager_load!)

    warm_up

    expect(i18n).to have_received(:eager_load!)
  end

  it "builds the route set's url helpers" do
    warm_up

    expect(routes).to have_received(:url_helpers)
  end

  it "eager-loads lazily drawn routes when the route set supports it" do
    allow(routes).to receive(:eager_load!)

    warm_up

    expect(routes).to have_received(:eager_load!)
  end

  it "resolves an asset path through the controller helpers" do
    helpers = double("helpers", stylesheet_path: "/assets/application.css")
    stub_const("ActionController::Base", double("ActionController::Base", helpers: helpers))

    warm_up

    expect(helpers).to have_received(:stylesheet_path).with("application")
  end

  it "precompiles templates when actionview_precompiler is installed" do
    allow(Gem.loaded_specs).to receive(:key?).and_call_original
    allow(Gem.loaded_specs).to receive(:key?).with("actionview_precompiler").and_return(true)
    precompiler = stub_const("ActionviewPrecompiler", Module.new)
    allow(precompiler).to receive(:precompile)
    warmup = described_class.new(app, stream: stream)
    allow(warmup).to receive(:require).with("actionview_precompiler").and_return(true)

    warmup.call

    expect(precompiler).to have_received(:precompile)
  end

  it "skips template precompilation when actionview_precompiler is not installed" do
    allow(Gem.loaded_specs).to receive(:key?).and_call_original
    allow(Gem.loaded_specs).to receive(:key?).with("actionview_precompiler").and_return(false)
    warmup = described_class.new(app, stream: stream)
    allow(warmup).to receive(:require)

    warmup.call

    expect(warmup).not_to have_received(:require)
  end

  it "skips steps whose library is not loaded, without a note" do
    hide_const("I18n")
    hide_const("ActionController::Base")

    warm_up

    expect(stream.string).to eq("")
  end

  # A warm-up step that does not fit an app (no application stylesheet, no
  # root route...) must never fail or skew the run.
  it "notes a failing step and carries on with the rest" do
    helpers = double("helpers")
    allow(helpers).to receive(:stylesheet_path).and_raise(ArgumentError, "asset not found")
    stub_const("ActionController::Base", double("ActionController::Base", helpers: helpers))
    i18n = stub_const("I18n", Module.new)
    allow(i18n).to receive(:eager_load!)

    expect { warm_up }.not_to raise_error

    expect(stream.string).to include("rails warmup: skipped assets (ArgumentError: asset not found)")
    expect(i18n).to have_received(:eager_load!)
    expect(routes).to have_received(:url_helpers)
  end

  it "notes a failing routes step and still runs the later steps" do
    allow(routes).to receive(:url_helpers).and_raise(RuntimeError, "no root route")
    helpers = double("helpers", stylesheet_path: "/assets/application.css")
    stub_const("ActionController::Base", double("ActionController::Base", helpers: helpers))

    expect { warm_up }.not_to raise_error

    expect(stream.string).to include("rails warmup: skipped routes (RuntimeError: no root route)")
    expect(helpers).to have_received(:stylesheet_path)
  end

  it "notes a failing templates step" do
    allow(Gem.loaded_specs).to receive(:key?).and_call_original
    allow(Gem.loaded_specs).to receive(:key?).with("actionview_precompiler").and_return(true)
    warmup = described_class.new(app, stream: stream)
    allow(warmup).to receive(:require).with("actionview_precompiler").and_raise(LoadError, "missing")

    expect { warmup.call }.not_to raise_error

    expect(stream.string).to include("rails warmup: skipped templates (LoadError: missing)")
  end

  it "requires actionview_precompiler before precompiling" do
    allow(Gem.loaded_specs).to receive(:key?).and_call_original
    allow(Gem.loaded_specs).to receive(:key?).with("actionview_precompiler").and_return(true)
    precompiler = stub_const("ActionviewPrecompiler", Module.new)
    allow(precompiler).to receive(:precompile)
    warmup = described_class.new(app, stream: stream)
    allow(warmup).to receive(:require).with("actionview_precompiler").and_return(true)

    warmup.call

    expect(warmup).to have_received(:require).with("actionview_precompiler")
  end

  # Older i18n releases have no I18n.eager_load!.
  it "skips i18n silently when I18n has no eager_load!" do
    stub_const("I18n", Module.new)

    warm_up

    expect(stream.string).to eq("")
  end

  it "notes a step that fails to load a library" do
    i18n = stub_const("I18n", Module.new)
    allow(i18n).to receive(:eager_load!).and_raise(LoadError, "cannot load such file -- yaml")

    expect { warm_up }.not_to raise_error

    expect(stream.string).to include("rails warmup: skipped i18n (LoadError: cannot load such file -- yaml)")
  end
end
