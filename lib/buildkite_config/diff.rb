require "diffy"

module Buildkite::Config
  class Diff
    def initialize(file, repo: "rails/buildkite-config", branch: "main")
      @file = file
      @repo = repo
      @branch = branch

      setup_repo "https://github.com/rails/rails.git" do |rails|
        setup_repo "https://github.com/#{repo}.git", branch: branch do |main|
          @head = generated_pipeline(".", rails)
          @main = generated_pipeline(main, rails)
        end
      end
    end

    def compare
      Diffy::Diff.new(@main, @head, allow_empty_diff: false, context: 4)
    end

    private
      def generated_pipeline(repo, rails)
        Dir.mktmpdir do |dir|
          `ruby #{repo}/#{@file} #{rails} > #{dir}/pipeline`
          File.read("#{dir}/pipeline")
        end
      end

      def setup_repo(repo, branch: "main", &block)
        Dir.mktmpdir do |dir|
          `git clone --depth=1 --branch=#{branch} #{repo} #{dir}`
          yield(dir)
        end
      end
  end
end