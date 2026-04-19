# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/config"
require "evilution/integration/rspec"

RSpec.describe "Per-mutation spec targeting (integration)" do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def write_file(path, contents = "")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def build_mutation(file_path)
    instance_double(
      Evilution::Mutation,
      file_path: file_path,
      original_source: File.read(file_path),
      mutated_source: "# mutated\n#{File.read(file_path)}",
      diff: nil
    )
  end

  def capture_runner_args
    captured = []
    allow(RSpec::Core::Runner).to receive(:run) do |args, _out, _err|
      captured << args
      0
    end
    captured
  end

  let(:games_controller_path) { "app/controllers/games_controller.rb" }
  let(:games_helper_path) { "app/helpers/games_helper.rb" }
  let(:games_request_spec) { "spec/requests/games_spec.rb" }
  let(:games_helper_spec) { "spec/helpers/games_helper_spec.rb" }
  let(:unrelated_spec) { "spec/news_spec.rb" }

  before do
    write_file(games_controller_path, "class GamesController; def index; end; end\n")
    write_file(games_helper_path, "module GamesHelper; def fmt(x); x.to_s; end; end\n")
    write_file(games_request_spec, "RSpec.describe 'games' do\n  it { expect(1).to eq(1) }\nend\n")
    write_file(games_helper_spec, "RSpec.describe 'games_helper' do\n  it { expect(1).to eq(1) }\nend\n")
    write_file(unrelated_spec, "RSpec.describe 'news' do\n  it { expect(1).to eq(1) }\nend\n")
    allow(RSpec).to receive(:clear_examples)
  end

  let(:config) { Evilution::Config.new(skip_config_file: true, integration: :rspec) }
  let(:integration) do
    inst = Evilution::Integration::RSpec.new(spec_selector: config.spec_selector)
    # Prevent host RSpec state corruption: real Runner is mocked, but the
    # integration's ensure block still mutates RSpec.world / configuration.
    allow(inst).to receive(:release_rspec_state)
    allow(inst).to receive(:release_filtered_examples)
    allow(inst).to receive(:release_reporter_state)
    inst
  end

  it "loads only spec/requests/games_spec.rb when targeting games_controller.rb" do
    captured = capture_runner_args

    integration.call(build_mutation(games_controller_path))

    args = captured.first
    expect(args).to include(games_request_spec)
    expect(args).not_to include(games_helper_spec)
    expect(args).not_to include(unrelated_spec)
    expect(args).not_to include("spec")
  end

  it "loads only spec/helpers/games_helper_spec.rb when targeting games_helper.rb" do
    captured = capture_runner_args

    integration.call(build_mutation(games_helper_path))

    args = captured.first
    expect(args).to include(games_helper_spec)
    expect(args).not_to include(games_request_spec)
    expect(args).not_to include(unrelated_spec)
    expect(args).not_to include("spec")
  end

  it "delegates resolution to Config#spec_selector instead of using the full spec/ tree" do
    expect(config.spec_selector).to receive(:call).with(games_controller_path).and_call_original
    capture_runner_args

    integration.call(build_mutation(games_controller_path))
  end

  it "never falls back to running the entire spec/ directory under the default heuristic" do
    captured = capture_runner_args

    integration.call(build_mutation(games_controller_path))
    integration.call(build_mutation(games_helper_path))

    captured.each do |args|
      expect(args).not_to include("spec")
      expect(args).not_to include(unrelated_spec)
    end
  end
end
