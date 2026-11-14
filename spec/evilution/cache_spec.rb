# frozen_string_literal: true

require "tmpdir"

RSpec.describe Evilution::Cache do
  # Stands in for Cache::Keys: a mutation's keys are what it says they are.
  let(:fake_keys) do
    Class.new do
      attr_reader :indexed

      def initialize(names = {})
        @names = names
      end

      def index(subjects)
        @indexed = subjects
      end

      def subject_key(mutation)
        mutation.skey
      end

      def mutation_key(mutation)
        mutation.mkey
      end

      def subject_names(file_path)
        @names[file_path]
      end
    end
  end

  let(:cache_dir) { Dir.mktmpdir("evilution_cache") }
  let(:keys) { fake_keys.new }
  let(:cache) { described_class.new(keys: keys, cache_dir: cache_dir) }

  after { FileUtils.rm_rf(cache_dir) }

  def mutation(skey: "s1", mkey: "m1", name: "Example#foo", file: "lib/example.rb")
    double("Mutation", skey: skey, mkey: mkey, file_path: file, subject: double("Subject", name: name))
  end

  let(:result_data) do
    { status: :killed, duration: 0.5, killing_test: "spec/example_spec.rb:10",
      test_command: "rspec spec/example_spec.rb", time_limit: nil }
  end

  def reopen
    described_class.new(keys: keys, cache_dir: cache_dir)
  end

  def cache_files
    Dir.glob(File.join(cache_dir, "**", "*.json"))
  end

  describe "layout" do
    it "keeps one file per source file under a directory of the format" do
      cache.store(mutation(file: "lib/my app/Example_2-b.rb"), result_data)
      cache.flush

      digest = Digest::SHA256.hexdigest("lib/my app/Example_2-b.rb")[0, 12]
      expect(cache_files).to eq([File.join(cache_dir, "v2", "lib_myapp_Example_2-b.rb-#{digest}.json")])
    end

    it "records the format and the source file in it" do
      cache.store(mutation, result_data)
      cache.flush

      expect(JSON.parse(File.read(cache_files.first))).to include("format" => 2, "path" => "lib/example.rb")
    end

    it "leaves no temporary file behind" do
      cache.store(mutation, result_data)
      cache.flush

      expect(Dir.glob(File.join(cache_dir, "**", "*")).select { |path| File.file?(path) }).to eq(cache_files)
    end

    it "lives in tmp/evilution_cache by default" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          default = described_class.new(keys: keys)
          default.store(mutation, result_data)
          default.flush

          expect(Dir.glob("tmp/evilution_cache/v2/*.json").length).to eq(1)
        end
      end
    end
  end

  describe "#fetch" do
    it "returns nil for an uncached mutation" do
      expect(cache.fetch(mutation)).to be_nil
    end

    it "returns what was stored for the mutation" do
      cache.store(mutation, result_data)

      expect(cache.fetch(mutation)).to eq(result_data)
    end

    it "keeps a survivor and a timeout's time limit" do
      cache.store(mutation(mkey: "a"), status: :survived, duration: 0.2, killing_test: nil,
                                       test_command: "rspec x", time_limit: nil)
      cache.store(mutation(mkey: "b"), status: :timeout, duration: 3.0, killing_test: nil,
                                       test_command: nil, time_limit: 2.5)
      cache.flush

      expect(reopen.fetch(mutation(mkey: "a"))).to include(status: :survived, test_command: "rspec x")
      expect(reopen.fetch(mutation(mkey: "b"))).to include(status: :timeout, time_limit: 2.5)
    end

    it "misses a mutation of the same subject under another subject key" do
      cache.store(mutation(skey: "s1"), result_data)

      expect(cache.fetch(mutation(skey: "s2"))).to be_nil
    end

    it "misses when the keys cannot key the mutation" do
      cache.store(mutation, result_data)

      expect(cache.fetch(mutation(skey: nil))).to be_nil
      expect(cache.fetch(mutation(mkey: nil))).to be_nil
    end

    it "answers for each source file from its own cache file" do
      cache.store(mutation(file: "lib/a.rb", mkey: "a"), result_data)
      cache.store(mutation(file: "lib/b.rb", mkey: "b"), result_data)
      cache.flush
      fresh = reopen

      expect(fresh.fetch(mutation(file: "lib/a.rb", mkey: "a"))).to eq(result_data)
      expect(fresh.fetch(mutation(file: "lib/b.rb", mkey: "b"))).to eq(result_data)
      expect(fresh.fetch(mutation(file: "lib/b.rb", mkey: "a"))).to be_nil
    end

    it "reads each cache file once however many mutations it answers for" do
      cache.store(mutation(mkey: "a"), result_data)
      cache.store(mutation(mkey: "b"), result_data)
      cache.flush
      fresh = reopen
      allow(File).to receive(:read).and_call_original

      fresh.fetch(mutation(mkey: "a"))
      fresh.fetch(mutation(mkey: "b"))
      fresh.fetch(mutation(mkey: "c"))

      expect(File).to have_received(:read).once
    end
  end

  describe "#store" do
    it "is a no-op when the keys cannot key the mutation" do
      cache.store(mutation(skey: nil), result_data)
      cache.flush

      expect(cache_files).to be_empty
    end

    it "is a no-op when the keys cannot tell the mutation apart within its subject" do
      cache.store(mutation(mkey: nil), result_data)
      cache.flush

      expect(cache_files).to be_empty
    end

    it "writes nothing until flushed" do
      cache.store(mutation, result_data)

      expect(cache_files).to be_empty
      expect(reopen.fetch(mutation)).to be_nil
    end

    it "persists across instances once flushed" do
      cache.store(mutation, result_data)
      cache.flush

      expect(reopen.fetch(mutation)).to eq(result_data)
    end

    it "creates the cache directory if missing" do
      nested_dir = File.join(cache_dir, "nested", "dir")
      nested = described_class.new(keys: keys, cache_dir: nested_dir)

      nested.store(mutation, result_data)
      nested.flush

      expect(File.directory?(nested_dir)).to be true
    end

    it "writes a source file's cache once however many of its mutations are stored" do
      allow(File).to receive(:rename).and_call_original

      2_000.times { |i| cache.store(mutation(mkey: "m#{i}"), result_data) }
      cache.flush

      expect(File).to have_received(:rename).once
      expect(reopen.fetch(mutation(mkey: "m1999"))).to eq(result_data)
    end

    it "writes the previous source file's cache when the run moves on to another file" do
      cache.store(mutation(file: "lib/a.rb"), result_data)
      cache.store(mutation(file: "lib/b.rb"), result_data)

      expect(reopen.fetch(mutation(file: "lib/a.rb"))).to eq(result_data)
      expect(reopen.fetch(mutation(file: "lib/b.rb"))).to be_nil
    end

    it "writes each source file once when the run goes through them in turn" do
      allow(File).to receive(:rename).and_call_original

      cache.store(mutation(file: "lib/a.rb", mkey: "1"), result_data)
      cache.store(mutation(file: "lib/a.rb", mkey: "2"), result_data)
      cache.store(mutation(file: "lib/b.rb"), result_data)
      cache.store(mutation(file: "lib/c.rb"), result_data)
      cache.flush
      cache.flush

      expect(File).to have_received(:rename).exactly(3).times
    end

    it "writes nothing for a file it only looked up when the run moves on" do
      allow(File).to receive(:rename).and_call_original

      cache.fetch(mutation(file: "lib/a.rb"))
      cache.store(mutation(file: "lib/b.rb"), result_data)
      cache.store(mutation(file: "lib/c.rb"), result_data)

      expect(File).to have_received(:rename).once
    end

    it "keeps the entries of other subjects of the file" do
      cache.store(mutation(skey: "s1", name: "Example#foo"), result_data)
      cache.flush
      second = reopen
      second.store(mutation(skey: "s2", name: "Example#bar"), result_data)
      second.flush

      expect(reopen.fetch(mutation(skey: "s1", name: "Example#foo"))).to eq(result_data)
    end
  end

  describe "#flush" do
    it "drops the entries of a subject's earlier version" do
      cache.store(mutation(skey: "old", name: "Example#foo"), result_data)
      cache.flush
      second = reopen
      second.store(mutation(skey: "new", name: "Example#foo"), result_data)
      second.flush

      expect(JSON.parse(File.read(cache_files.first))["subjects"].keys).to eq(["new"])
    end

    it "drops the entries of a subject the file no longer has" do
      cache.store(mutation(skey: "gone", name: "Example#gone"), result_data)
      cache.flush
      second = described_class.new(keys: fake_keys.new("lib/example.rb" => ["Example#foo"]), cache_dir: cache_dir)
      second.store(mutation(skey: "s1", name: "Example#foo"), result_data)
      second.flush

      expect(JSON.parse(File.read(cache_files.first))["subjects"].keys).to eq(["s1"])
    end

    it "keeps a subject the file still has though the run did not look it up" do
      cache.store(mutation(skey: "other", name: "Example#bar"), result_data)
      cache.flush
      second = described_class.new(keys: fake_keys.new("lib/example.rb" => ["Example#foo", "Example#bar"]),
                                   cache_dir: cache_dir)
      second.store(mutation(skey: "s1", name: "Example#foo"), result_data)
      second.flush

      expect(JSON.parse(File.read(cache_files.first))["subjects"].keys).to contain_exactly("s1", "other")
    end

    it "keeps a version of a subject the run found in the cache beside one it stored" do
      cache.store(mutation(skey: "first", name: "Example#foo"), result_data)
      cache.flush
      second = reopen
      second.fetch(mutation(skey: "first", name: "Example#foo"))
      second.store(mutation(skey: "second", name: "Example#foo"), result_data)
      second.flush

      expect(JSON.parse(File.read(cache_files.first))["subjects"].keys).to contain_exactly("first", "second")
    end

    it "drops an earlier version of a subject the run found in the cache" do
      cache.store(mutation(skey: "old", name: "Example#foo"), result_data)
      cache.store(mutation(skey: "current", name: "Example#foo"), result_data)
      cache.flush
      second = described_class.new(keys: fake_keys.new("lib/example.rb" => ["Example#foo", "Example#bar"]),
                                   cache_dir: cache_dir)
      second.fetch(mutation(skey: "current", name: "Example#foo"))
      second.store(mutation(skey: "bar", name: "Example#bar"), result_data)
      second.flush

      expect(JSON.parse(File.read(cache_files.first))["subjects"].keys).to contain_exactly("current", "bar")
    end

    it "judges what to drop file by file" do
      cache.store(mutation(file: "lib/b.rb", skey: "b-old", name: "Example#foo"), result_data)
      cache.flush
      second = reopen
      second.store(mutation(file: "lib/a.rb", skey: "a-new", name: "Example#foo"), result_data)
      second.store(mutation(file: "lib/b.rb", skey: "b-other", name: "Example#bar"), result_data)
      second.flush

      expect(reopen.fetch(mutation(file: "lib/b.rb", skey: "b-old", name: "Example#foo"))).to eq(result_data)
    end

    it "keeps two subjects of the same name" do
      cache.store(mutation(skey: "first", name: "Example#foo"), result_data)
      cache.store(mutation(skey: "second", name: "Example#foo"), result_data)
      cache.flush

      expect(reopen.fetch(mutation(skey: "first"))).to eq(result_data)
      expect(reopen.fetch(mutation(skey: "second"))).to eq(result_data)
    end

    it "removes cache files of the earlier format" do
      FileUtils.mkdir_p(cache_dir)
      legacy = File.join(cache_dir, "lib_example.rb_0123456789abcdef.json")
      File.write(legacy, "{}")

      cache.store(mutation, result_data)
      cache.flush

      expect(File.exist?(legacy)).to be false
    end

    it "writes nothing from a forked child" do
      cache.store(mutation, result_data)
      pid = fork do
        cache.store(mutation(file: "lib/other.rb"), result_data)
        cache.flush
        exit!(0)
      end
      Process.wait(pid)

      expect(cache_files).to be_empty
    end
  end

  describe "#index" do
    it "hands the subjects to the keys" do
      subjects = [double("Subject")]
      cache.index(subjects)

      expect(keys.indexed).to eq(subjects)
    end
  end

  describe "#clear" do
    it "removes all cached data" do
      cache.store(mutation, result_data)
      cache.flush
      cache.clear

      expect(cache.fetch(mutation)).to be_nil
      expect(reopen.fetch(mutation)).to be_nil
    end
  end

  describe "unreadable cache files" do
    def write_cache_file(content)
      cache.store(mutation, result_data)
      cache.flush
      File.write(cache_files.first, content)
    end

    it "ignores a file that is not JSON" do
      write_cache_file("{not json")

      expect(reopen.fetch(mutation)).to be_nil
    end

    def valid_subjects
      { "s1" => { "name" => "x", "mutations" => { "m1" => { "status" => "killed", "duration" => 1.0 } } } }
    end

    it "reads a file of this format" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT, "subjects" => valid_subjects))

      expect(reopen.fetch(mutation)).to include(status: :killed, duration: 1.0)
    end

    it "ignores a file of another format" do
      write_cache_file(JSON.generate("format" => 1, "subjects" => valid_subjects))

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "ignores a file that holds no object" do
      write_cache_file("[1]")

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "ignores a file whose subjects are not an object" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT, "subjects" => [1]))

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "ignores a subject whose mutations are not an object" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT,
                                     "subjects" => { "s1" => { "name" => "x", "mutations" => [1] } }))

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "ignores an entry whose status is not a string" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT,
                                     "subjects" => { "s1" => { "name" => "x", "mutations" => {
                                       "m1" => { "status" => 1, "duration" => 1.0 }
                                     } } }))

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "ignores entries of the wrong shape" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT,
                                     "subjects" => { "s1" => { "name" => "x", "mutations" => { "m1" => "corrupted" } } }))

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "ignores an entry without a status" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT,
                                     "subjects" => { "s1" => { "name" => "x", "mutations" => { "m1" => {} } } }))

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "ignores an entry whose duration is not a number" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT,
                                     "subjects" => { "s1" => { "name" => "x", "mutations" => {
                                       "m1" => { "status" => "killed", "duration" => "slow" }
                                     } } }))

      expect(reopen.fetch(mutation)).to be_nil
    end

    it "drops a time limit that is not a number" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT,
                                     "subjects" => { "s1" => { "name" => "x", "mutations" => {
                                       "m1" => { "status" => "timeout", "duration" => 1.0, "time_limit" => "x" }
                                     } } }))

      expect(reopen.fetch(mutation)).to include(status: :timeout, duration: 1.0, time_limit: nil)
    end

    it "ignores a subject entry without mutations and stores over it" do
      write_cache_file(JSON.generate("format" => described_class::FORMAT, "subjects" => { "s1" => "corrupted" }))
      fresh = reopen
      fresh.store(mutation, result_data)
      fresh.flush

      expect(reopen.fetch(mutation)).to eq(result_data)
    end
  end
end
