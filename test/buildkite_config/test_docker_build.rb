# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestDockerBuild < TestCase
  def test_builder
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerBuild

      builder ruby: "3.2"
    end

    expected = {"steps"=>
      [{"label"=>":docker: 3.2",
        "key"=>"docker-image-3-2",
        "agents"=>{"queue"=>"builder"},
        "env"=>
         {"RUBY_IMAGE"=>"3.2",
          "encrypted_0fb9444d0374_key"=>nil,
          "encrypted_0fb9444d0374_iv"=>nil},
        "timeout_in_minutes"=>15,
        "plugins"=>
         [{"artifacts#v1.2.0"=>
            {"download"=>[".dockerignore", ".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"build"=>"base",
            "config"=>".buildkite/docker-compose.yml",
            "env"=>["PRE_STEPS", "RACK"],
            "image-name"=>"3-2-local",
            "cache-from"=>["base:buildkite-config-base:3-2-br-main"],
            "push"=>["base:buildkite-config-base:3-2-br-"],
            "image-repository"=>"buildkite-config-base"}}]}]}
    assert_equal expected, pipeline.to_h
  end
end
