# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestRakeCommand < TestCase
  def test_to_label
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      ruby = Buildkite::Config::RubyConfig.new(version: "3.2")

      group do
        label to_label(ruby, "test", "test:all")
      end
    end

    expected = {"steps" => [{ "label" => "test all (3.2)", "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_ruby_image_name
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: "3.2")

      group do
        depends_on build_context.ruby.ruby_image
      end
    end

    expected = {"steps" => [{ "depends_on" => ["3.2"], "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_depends_on_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Buildkite::Config::RubyConfig.yjit_ruby)

      group do
        depends_on build_context.ruby.ruby_image
      end
    end

    expected = {"steps" => [{ "depends_on" => ["rubylang/ruby:master-nightly-jammy"], "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_command
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake "test", "test:all"
    end

    expected = {"steps"=>
      [{"label"=>"test all (3.2)",
        "command"=>["rake test:all"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", "test"]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_multiple
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake "first", "test:all"
      rake "second", "test:all"
    end

    expected = {"steps"=>
      [{"label"=>"first all (3.2)",
        "command"=>["rake test:all"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", "first"]}}]},
      {"label"=>"second all (3.2)",
        "command"=>["rake test:all"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", "second"]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_docker_compose_plugin
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake "subdirectory", "test:isolated", service: "myservice"
    end

    expected = {"steps"=>
      [{"label"=>"subdirectory isolated (3.2)",
        "command"=>["rake test:isolated"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"myservice",
            "pull"=>"myservice",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", "subdirectory"]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_env_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      build_context.ruby = Buildkite::Config::RubyConfig.new(
        version: Buildkite::Config::RubyConfig.yjit_ruby, image_base: build_context.image_base)
      rake
    end

    expected = {"steps"=>
      [{"label"=>"  (yjit)",
        "command"=>["rake "],
        "depends_on"=>["docker-image-yjit-rubylang-ruby-master-nightly-jammy"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:rubylang-ruby-master-nightly-jammy-local", "RUBY_YJIT_ENABLE"=>"1"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", ""]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_env_pre_steps
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake pre_steps: ["rm Gemfile.lock", "bundle install"] do
        label "test_env_pre_steps"
      end
    end

    expected = {"steps"=>
      [{"label"=>"test_env_pre_steps",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local", "PRE_STEPS"=>"rm Gemfile.lock && bundle install"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", ""]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_agents
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake do
        label "test_agents"
        agents queue: "test_agents"
      end
    end

    expected = {"steps"=>
      [{"label"=>"test_agents",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"test_agents"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", ""]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_artifact_paths
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake do
        label "test_artifact_paths"
        artifact_paths ["test_artifact_paths"]
      end
    end

    expected = {"steps"=>
      [{"label"=>"test_artifact_paths",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "agents"=>{"queue"=>"default"},
        "artifact_paths"=>["test_artifact_paths"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", ""]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_automatic_retry_on
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake do |attrs|
        label "test_automatic_retry_on"
        # Reset "automatic_retry_on" from the default
        # Since this does a push, and we only want a single value, I think.
        attrs["retry"] = nil
        automatic_retry_on limit: 1, exit_status: 127
      end
    end

    expected = {"steps"=>
      [{"label"=>"test_automatic_retry_on",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "retry"=>{"automatic"=>[{"limit"=>1, "exit_status"=>127}]},
        "agents"=>{"queue"=>"default"},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", ""]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_timeout_in_minutes
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake do
        label "test_timeout_in_minutes"
        timeout_in_minutes 10
      end
    end

    expected = {"steps"=>
      [{"label"=>"test_timeout_in_minutes",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "agents"=>{"queue"=>"default"},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "timeout_in_minutes"=>10,
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", ""]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_soft_fail
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake do
        label "soft_fail"
        soft_fail true
      end
    end

    expected = {"steps"=>
      [{"label"=>"soft_fail",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "soft_fail"=>true,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", ""]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_rake_with_block
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      rake "test", "all" do |attrs|
        label "#{attrs["label"]} with_block"
        env["MYSQL_IMAGE"] = "mariadb:latest"
      end
    end

    expected = {"steps"=>
      [{"label"=>"test all (3.2) with_block",
        "command"=>["rake all"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-reports/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local", "MYSQL_IMAGE"=>"mariadb:latest"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", "test"]}}]}]}
    assert_equal expected, pipeline.to_h
  end
end
