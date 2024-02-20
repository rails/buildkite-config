# frozen_string_literal: true

require "diffy"

module Buildkite::Config
  module Diff
    def self.compare(nightly: false)
      head = generated_pipeline(Dir.pwd, nightly: nightly)
      main = generated_pipeline(File.expand_path("tmp/buildkite-config", Dir.pwd), nightly: nightly)
      Diffy::Diff.new(main, head, context: 4)
    end

    def self.generated_pipeline(repo, nightly: false)
      File.symlink(repo, "tmp/rails/.buildkite")

      command = ["ruby", ".buildkite/pipeline-generate"]

      pipeline = "rails-ci"
      pipeline += "-nightly" if nightly
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
