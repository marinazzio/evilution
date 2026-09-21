# frozen_string_literal: true

require "English"
require "tmpdir"

RSpec.describe "executables" do
  let(:exe_dir) { File.expand_path("../exe", __dir__) }
  let(:evilution_path) { File.join(exe_dir, "evilution") }
  let(:evil_path) { File.join(exe_dir, "evil") }

  it "ships an 'evilution' executable" do
    expect(File.executable?(evilution_path)).to be true
  end

  it "ships an 'evil' alternative executable" do
    expect(File.executable?(evil_path)).to be true
  end

  # EV-g8ya / GH #1608: --preload loads the project's spec helper into this
  # process, and SimpleCov's at_exit hook calls exit with its own status. The
  # guard the executable installs has to outlast it.
  it "keeps its own exit status when a preloaded at_exit hook exits non-zero" do
    Dir.mktmpdir do |dir|
      helper = File.join(dir, "helper.rb")
      File.write(helper, "at_exit { puts 'coverage report'; exit 2 }\n")
      script = File.join(dir, "run.rb")
      File.write(script, <<~RUBY)
        $LOAD_PATH.unshift(#{File.expand_path("../lib", __dir__).inspect})
        require "evilution"
        guard = Evilution::CLI::ExitGuard.new.install
        require #{helper.inspect}
        guard.status = 0
        exit guard.status
      RUBY

      output = `#{RbConfig.ruby} #{script} 2>&1`

      expect([$CHILD_STATUS.exitstatus, output]).to eq([0, "coverage report\n"])
    end
  end

  it "evil has identical contents to evilution" do
    aggregate_failures do
      expect(File.exist?(evil_path)).to be true
      expect(File.exist?(evilution_path)).to be true
      expect(File.binread(evil_path)).to eq(File.binread(evilution_path))
    end
  end
end
