# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestDockerCompose < TestCase
  def test_to_label
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      group do
        label my_context.to_label(subdirectory: "test", rake_task: "test:all", ruby: "3.2")
      end
    end

    expected = {"steps" => [{ "label" => "test all (3.2)", "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_ruby_image
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      group do
        depends_on my_context.ruby_image("3.2")
      end
    end

    expected = {"steps" => [{ "depends_on" => ["3.2"], "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_depends_on_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      group do
        depends_on my_context.ruby_image(my_context.yjit_ruby)
      end
    end

    expected = {"steps" => [{ "depends_on" => ["rubylang/ruby:master-nightly-jammy"], "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_command
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose subdirectory: "test", rake_task: "test:all"
    end

    expected = {"steps"=>
      [{"label"=>"test all",
        "command"=>["rake test:all"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
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
      use Buildkite::Config::DockerCompose

      compose subdirectory: "first", rake_task: "test:all"
      compose subdirectory: "second", rake_task: "test:all"
    end

    expected = {"steps"=>
      [{"label"=>"first all",
        "command"=>["rake test:all"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
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
      {"label"=>"second all",
        "command"=>["rake test:all"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
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
      use Buildkite::Config::DockerCompose

      compose service: "myservice", subdirectory: "subdirectory", rake_task: "test:isolated"
    end

    expected = {"steps"=>
      [{"label"=>"subdirectory isolated",
        "command"=>["rake test:isolated"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
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
      use Buildkite::Config::DockerCompose

      compose ruby: my_context.yjit_ruby
    end

    expected = {"steps"=>
      [{"label"=>"  (yjit)",
        "command"=>["rake "],
        "depends_on"=>["docker-image-rubylang-ruby-master-nightly-jammy"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:rubylang-ruby-master-nightly-jammy-local", "RUBY_YJIT_ENABLE"=>"1"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", nil]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_env_pre_steps
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose pre_steps: ["rm Gemfile.lock", "bundle install"]
    end

    expected = {"steps"=>
      [{"label"=>" ",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local", "PRE_STEPS"=>"rm Gemfile.lock && bundle install"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", nil]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_agents
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose do
        agents queue: "test_agents"
      end
    end

    expected = {"steps"=>
      [{"label"=>" ",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"test_agents"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", nil]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_artifact_paths
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose do
        artifact_paths ["test_artifact_paths"]
      end
    end

    expected = {"steps"=>
      [{"label"=>" ",
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
            "shell"=>["runner", nil]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_automatic_retry_on
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose do |attrs|
        # Reset "automatic_retry_on" from the default
        # Since this does a push, and we only want a single value, I think.
        attrs["retry"] = nil
        automatic_retry_on limit: 1, exit_status: 127
      end
    end

    expected = {"steps"=>
      [{"label"=>" ",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "retry"=>{"automatic"=>[{"limit"=>1, "exit_status"=>127}]},
        "agents"=>{"queue"=>"default"},
        "artifact_paths"=>["test-results/*/*.xml"],
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "timeout_in_minutes"=>30,
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", nil]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_timeout_in_minutes
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose do
        timeout_in_minutes 10
      end
    end

    expected = {"steps"=>
      [{"label"=>" ",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "agents"=>{"queue"=>"default"},
        "artifact_paths"=>["test-results/*/*.xml"],
        "timeout_in_minutes"=>10,
        "env"=>{"IMAGE_NAME"=>"buildkite-config-base:3-2-local"},
        "plugins"=>
        [{"artifacts#v1.2.0"=>{"download"=>[".buildkite/*", ".buildkite/*/*"]}},
          {"docker-compose#v3.7.0"=>
            {"env"=>["PRE_STEPS", "RACK"],
            "run"=>"default",
            "pull"=>"default",
            "config"=>".buildkite/docker-compose.yml",
            "shell"=>["runner", nil]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_soft_fail
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose soft_fail: true
    end

    expected = {"steps"=>
      [{"label"=>" ",
        "command"=>["rake "],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
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
            "shell"=>["runner", nil]}}]}]}
    assert_equal expected, pipeline.to_h
  end

  def test_compose_with_block
    pipeline = PipelineFixture.new do
      use Buildkite::Config::DockerCompose

      compose subdirectory: "test", rake_task: "compose" do |attrs|
        label "#{attrs["label"]} with_block"
        env["MYSQL_IMAGE"] = "mariadb:latest"
      end
    end

    expected = {"steps"=>
      [{"label"=>"test compose with_block",
        "command"=>["rake compose"],
        "depends_on"=>["docker-image-3-2"],
        "agents"=>{"queue"=>"default"},
        "retry"=>{"automatic"=>[{"limit"=>2, "exit_status"=>-1}]},
        "artifact_paths"=>["test-results/*/*.xml"],
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
