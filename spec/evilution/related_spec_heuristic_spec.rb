# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "evilution/related_spec_heuristic"

RSpec.describe Evilution::RelatedSpecHeuristic do
  subject(:heuristic) { described_class.new }

  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def create_file(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
  end

  describe "#call" do
    context "when mutation removes .includes()" do
      let(:mutation) do
        double("Mutation",
               file_path: "app/controllers/news_controller.rb",
               diff: "- News.includes(:comments).where(published: true)\n+ News.where(published: true)")
      end

      it "finds matching request specs" do
        create_file("spec/requests/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/news_spec.rb")
      end

      it "finds matching integration specs" do
        create_file("spec/integration/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/integration/news_spec.rb")
      end

      it "finds matching feature specs" do
        create_file("spec/features/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/features/news_spec.rb")
      end

      it "finds matching system specs" do
        create_file("spec/system/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/system/news_spec.rb")
      end

      it "finds specs in subdirectories" do
        create_file("spec/requests/api/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/api/news_spec.rb")
      end

      it "returns multiple matching specs" do
        create_file("spec/requests/news_spec.rb")
        create_file("spec/features/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result.length).to eq(2)
      end

      it "returns empty array when no related specs exist" do
        result = heuristic.call(mutation)

        expect(result).to eq([])
      end
    end

    context "when mutation is in a model file" do
      let(:mutation) do
        double("Mutation",
               file_path: "app/models/news.rb",
               diff: "- News.includes(:author).order(created_at: :desc)\n" \
                     "+ News.order(created_at: :desc)")
      end

      it "finds request specs matching the model domain" do
        create_file("spec/requests/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/news_spec.rb")
      end
    end

    context "when mutation does not involve .includes()" do
      let(:mutation) do
        double("Mutation",
               file_path: "app/controllers/news_controller.rb",
               diff: "- x >= 10\n+ x > 10")
      end

      it "returns empty array" do
        create_file("spec/requests/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to eq([])
      end
    end

    context "domain extraction" do
      it "strips _controller suffix from controller files" do
        mutation = double("Mutation",
                          file_path: "app/controllers/posts_controller.rb",
                          diff: "- Post.includes(:tags)\n+ Post")
        create_file("spec/requests/posts_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/posts_spec.rb")
      end

      it "uses basename for model files" do
        mutation = double("Mutation",
                          file_path: "app/models/article.rb",
                          diff: "- Article.includes(:comments)\n+ Article")
        create_file("spec/requests/article_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/article_spec.rb")
      end

      it "handles namespaced paths" do
        mutation = double("Mutation",
                          file_path: "app/controllers/admin/users_controller.rb",
                          diff: "- User.includes(:roles)\n+ User")
        create_file("spec/requests/admin/users_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/admin/users_spec.rb")
      end
    end

    context "implicit receiver includes" do
      it "matches includes without dot prefix" do
        mutation = double("Mutation",
                          file_path: "app/models/news.rb",
                          diff: "- scope :recent, -> { includes(:author) }\n+ scope :recent, -> { all }")
        create_file("spec/requests/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/news_spec.rb")
      end
    end

    context "absolute paths" do
      it "normalizes absolute paths before extracting domain" do
        abs_path = "#{Dir.pwd}/app/controllers/news_controller.rb"
        mutation = double("Mutation",
                          file_path: abs_path,
                          diff: "- News.includes(:comments)\n+ News")
        create_file("spec/requests/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/news_spec.rb")
      end

      it "normalizes dot-prefixed paths" do
        mutation = double("Mutation",
                          file_path: "./app/models/news.rb",
                          diff: "- News.includes(:comments)\n+ News")
        create_file("spec/requests/news_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/news_spec.rb")
      end
    end

    context "edge cases" do
      it "handles nil diff gracefully" do
        mutation = double("Mutation",
                          file_path: "app/models/news.rb",
                          diff: nil)

        expect(heuristic.call(mutation)).to eq([])
      end

      it "handles lib/ paths" do
        mutation = double("Mutation",
                          file_path: "lib/news_fetcher.rb",
                          diff: "- News.includes(:source)\n+ News")
        create_file("spec/requests/news_fetcher_spec.rb")

        result = heuristic.call(mutation)

        expect(result).to include("spec/requests/news_fetcher_spec.rb")
      end
    end
  end
end
