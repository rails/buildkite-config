# frozen_string_literal: true

require "diffy"

module Buildkite::Config
  module Diff
    def self.compare
      head = generated_pipeline(Dir.pwd)
      main = generated_pipeline(File.expand_path("tmp/buildkite-config", Dir.pwd))
      Diffy::Diff.new(main, head, context: 4)
    end

    def self.generated_pipeline(repo)
      File.symlink(repo, "tmp/rails/.buildkite")

      command = ["ruby", ".buildkite/pipeline-generate"]

      pipeline = "rails-ci"
      command.push(pipeline)

      Dir.chdir("tmp/rails") do
        io = IO.popen(command)
        output = io.read
        io.close

        unless $?.success?
          $stderr.puts "Failed to generate pipeline for #{repo}"

          return ""
        end

        output
      end
    ensure
      File.unlink("tmp/rails/.buildkite")
    end
  end
end
