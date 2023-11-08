# frozen_string_literal: true

require "minitest/autorun"
require "buildkite-builder"

require "active_support/all"

BUILDKITE_CONFIG_ROOT = Pathname.new(File.expand_path("../..", __dir__))

class PipelineFixture < Buildkite::Builder::Pipeline
  def initialize(root = BUILDKITE_CONFIG_ROOT, logger: nil, &block)
    @pipeline_definition = Proc.new(&block)
    super(root, logger: logger)
  end
end

class TestCase < Minitest::Test
  make_my_diffs_pretty!

  def build_pipeline(data)
    {
      steps: [

      ]
    }
  end
end