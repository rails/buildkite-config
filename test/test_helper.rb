# frozen_string_literal: true

require "minitest/autorun"
require "buildkite-builder"

require "active_support"
require "active_support/test_case"

require "pathname"
BUILDKITE_CONFIG_ROOT = Pathname.new(File.expand_path("../..", __dir__))

module TestHelpers
  def plugins_map
    {
      compose: "docker-compose#v5.4.1",
      artifacts: "artifacts#v1.9.3"
    }
  end
end

class PipelineFixture < Buildkite::Builder::Pipeline
  include TestHelpers

  def initialize(root = BUILDKITE_CONFIG_ROOT, logger: nil, &block)
    @pipeline_definition = Proc.new(&block)
    super(root, logger: logger)
    use(Buildkite::Config::BuildContext)

    plugins = extensions.find(Buildkite::Builder::Extensions::Plugins)
    plugins.manager.add :docker_compose, plugins_map[:compose]
    plugins.manager.add :artifacts, plugins_map[:artifacts]
  end
end

class TestCase < ActiveSupport::TestCase
  include TestHelpers
  make_my_diffs_pretty!

  def setup
    @before_docker_image = ENV["DOCKER_IMAGE"]
    @before_buildkite_build_id = ENV["BUILDKITE_BUILD_ID"]
    ENV["BUILDKITE_BUILD_ID"] = "local"
    ENV["DOCKER_IMAGE"] = "buildkite-config-base"
  end

  def teardown
    ENV["DOCKER_IMAGE"] = @before_docker_image
    ENV["BUILDKITE_BUILD_ID"] = @before_buildkite_build_id
  end

  def build_pipeline(data)
    {
      steps: [

      ]
    }
  end
end
