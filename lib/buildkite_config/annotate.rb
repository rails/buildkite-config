module Buildkite::Config
  class Annotate
    def initialize(diff, nightly: false)
      @diff = diff
      @nightly = nightly
    end

    def perform
      return if @diff.to_s.empty?

      io = IO.popen("buildkite-agent annotate --style warning '#{plan}'")
      output = io.read
      io.close

      raise output unless $?.success?

      output
    end

    private
      def plan
        <<~PLAN
          ### :writing_hand: buildkite-config#{"-nightly" if @nightly}/plan

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
