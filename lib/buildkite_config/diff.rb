require "diffy"

module Buildkite::Config
  module Diff
    def self.compare
      head = generated_pipeline(".")
      main = generated_pipeline("tmp/buildkite-config")
      Diffy::Diff.new(main, head, context: 4)
    end

    def self.generated_pipeline(repo)
      io = IO.popen "ruby #{repo}/pipeline-generate tmp/rails"

      output = io.read
      io.close

      raise output unless $?.success?

      output
    end
  end
end

