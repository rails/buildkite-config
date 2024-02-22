# frozen_string_literal: true

module Buildkite::Config
  class Annotate
    def initialize(diff)
      @diff = diff
      @nightly = ENV.has_key?("RAILS_CI_NIGHTLY")
    end

    def plan
      return if @diff.to_s.empty?

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
