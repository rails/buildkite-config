# frozen_string_literal: true

require "diffy"

module Buildkite::Config
  module Diff
    def self.compare(nightly: false)
      head = generated_pipeline(".", nightly: nightly)
      main = generated_pipeline("tmp/buildkite-config", nightly: nightly)
      Diffy::Diff.new(main, head, context: 4)
    end

    def self.generated_pipeline(repo, nightly: false)
      command = if nightly
        "pipeline-generate-nightly"
      else
        "pipeline-generate"
      end

      io = IO.popen "ruby #{repo}/#{command} tmp/rails"

      output = io.read
      io.close

      unless $?.success?
        $stderr.puts "Failed to generate pipeline for #{repo}"

        return ""
      end

      output
    end
  end
end
