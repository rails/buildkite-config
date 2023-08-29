require "tempfile"

module Buildkite::Config
  class Annotate
    def initialize(diff)
      @diff = diff
    end

    def perform
      return if @diff.to_s.empty?

      file = Tempfile.new("generate-pipeline.diff")
      file.write plan
      file.close

      io = IO.popen("printf '%b\n' \"$(cat #{file.path})\" | buildkite-agent annotate --style warning")
      output = io.read
      io.close

      raise output unless $?.success?

      output
    end

    private
      def plan
        <<~PLAN
          ### :writing_hand: buildkite-config/plan

          <details>
          <summary>Show Output</summary>

          ```term
          #{@diff.to_s(:color)}
          ```

          </details>
        PLAN
      end
  end
end