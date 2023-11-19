# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestDockerBuild < TestCase
  def test_builder
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerBuild

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        builder ruby: Buildkite::Config::RubyConfig.new(prefix: "builder:", version: "3.2")
      end
    end

    expected = { "steps" =>
      [{ "label" => ":docker: builder:3.2",
        "key" => "docker-image-builder-3-2",
        "agents" => { "queue" => "builder" },
        "env" =>
         { "BUNDLER" => nil,
          "RUBYGEMS" => nil,
          "RUBY_IMAGE" => "builder:3.2",
          "encrypted_0fb9444d0374_key" => nil,
          "encrypted_0fb9444d0374_iv" => nil },
        "timeout_in_minutes" => 15,
        "plugins" =>
         [{ "artifacts#v1.2.0" =>
            { "download" => [".dockerignore", ".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v3.7.0" =>
            { "build" => "base",
            "config" => ".buildkite/docker-compose.yml",
            "env" => ["PRE_STEPS", "RACK"],
            "image-name" => "builder-3-2-local",
            "cache-from" => ["base:buildkite-config-base:builder-3-2-br-main"],
            "push" => ["base:buildkite-config-base:builder-3-2-br-"],
            "image-repository" => "buildkite-config-base" } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_builder_gem_version
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerBuild

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        builder ruby: Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("1.9.3"))
      end
    end

    expected = { "steps" =>
      [{ "label" => ":docker: ruby:1.9.3",
        "key" => "docker-image-ruby-1-9-3",
        "agents" => { "queue" => "builder" },
        "env" =>
         { "BUNDLER" => nil,
          "RUBYGEMS" => nil,
          "RUBY_IMAGE" => "ruby:1.9.3",
          "encrypted_0fb9444d0374_key" => nil,
          "encrypted_0fb9444d0374_iv" => nil },
        "timeout_in_minutes" => 15,
        "plugins" =>
         [{ "artifacts#v1.2.0" =>
            { "download" => [".dockerignore", ".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v3.7.0" =>
            { "build" => "base",
            "config" => ".buildkite/docker-compose.yml",
            "env" => ["PRE_STEPS", "RACK"],
            "image-name" => "ruby-1-9-3-local",
            "cache-from" => ["base:buildkite-config-base:ruby-1-9-3-br-main"],
            "push" => ["base:buildkite-config-base:ruby-1-9-3-br-"],
            "image-repository" => "buildkite-config-base" } }] }] }
    assert_equal expected, pipeline.to_h
  end
end
