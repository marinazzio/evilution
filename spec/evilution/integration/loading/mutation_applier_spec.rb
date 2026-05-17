# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/integration/loading/mutation_applier"

RSpec.describe Evilution::Integration::Loading::MutationApplier do
  subject(:applier) { described_class.new }

  let(:project_dir) { Dir.mktmpdir("evilution_applier") }
  let(:lib_dir) { File.join(project_dir, "lib") }
  let(:source_path) { File.join(lib_dir, "widget.rb") }
  let(:part_path) { File.join(lib_dir, "widget", "part.rb") }

  let(:original_source) do
    <<~RUBY
      class EkaxClobberWidget
        def self.value
          1
        end
      end
      require_relative "widget/part"
    RUBY
  end

  let(:mutated_source) { original_source.sub("    1", "    2") }

  let(:mutation) do
    double(
      "Mutation",
      file_path: source_path,
      original_source: original_source,
      mutated_source: mutated_source
    )
  end

  before do
    FileUtils.mkdir_p(File.join(lib_dir, "widget"))
    File.write(source_path, original_source)
    # Sibling that requires the parent file back — the pattern that triggers
    # the self-clobber: a lazy-loaded file whose own body re-`require`s itself
    # transitively through a sibling.
    File.write(part_path, %(require_relative "../widget"\n))
  end

  after do
    FileUtils.rm_rf(project_dir)
    Object.send(:remove_const, :EkaxClobberWidget) if Object.const_defined?(:EkaxClobberWidget)
    [source_path, part_path].each do |p|
      real = File.realpath(File.expand_path(p))
      $LOADED_FEATURES.delete(real)
    rescue Errno::ENOENT
      nil
    end
  end

  it "applies the mutation even when the file's own require_relative chain " \
     "loops back to it before it is registered in $LOADED_FEATURES" do
    applier.call(mutation)

    expect(EkaxClobberWidget.value).to eq(2)
  end
end
