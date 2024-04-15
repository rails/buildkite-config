# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestRakeCommand < TestCase
  def test_to_label
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))

      command do
        label to_label(ruby, "test", "test:all")
      end
    end

    expected = { "steps" => [{ "label" => "test all (3.2)" }] }
    assert_equal expected, pipeline.to_h
  end

  def test_ruby_image_key
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      ruby = Buildkite::Config::RubyConfig.new(version: "3.2", prefix: "ruby:")

      command do
        depends_on ruby.image_key
      end
    end

    expected = { "steps" => [{ "depends_on" => ["ruby-3-2"] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_depends_on_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      ruby = Buildkite::Config::RubyConfig.yjit_ruby

      command do
        depends_on ruby.ruby_image
      end
    end

    expected = { "steps" => [{ "depends_on" => ["rubylang/ruby:master-nightly-jammy"] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_command
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    expected = { "steps" =>
      [{ "label" => "test all (3.2)",
        "command" => ["rake test:all"],
        "depends_on" => ["docker-image-ruby-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:ruby-3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "test"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_default_task
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "activerecord"
      end
    end

    expected = { "steps" =>
      [{ "label" => "activerecord (3.2)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-ruby-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:ruby-3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "activerecord"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_multiple
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "first", task: "test:all"
        rake "second", task: "test:all"
      end
    end

    expected = { "steps" =>
      [{ "label" => "first all (3.2)",
        "command" => ["rake test:all"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "first"] } }] },
      { "label" => "second all (3.2)",
        "command" => ["rake test:all"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "second"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_docker_compose_plugin
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "subdirectory", service: "myservice"
      end
    end

    expected = { "steps" =>
      [{ "label" => "subdirectory (3.2)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "artifact_paths" => ["test-reports/*/*.xml"],
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "myservice",
            "pull" => "myservice",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "subdirectory"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_env_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      build_context.ruby = Buildkite::Config::RubyConfig.yjit_ruby
      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_env_yjit"
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_env_yjit (yjit)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-rubylang-ruby-master-nightly-jammy"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:rubylang-ruby-master-nightly-jammy-local", "RUBY_YJIT_ENABLE" => "1" },
        "soft_fail" => true,
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "test_env_yjit"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_env_pre_steps
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_env_pre_steps", pre_steps: ["rm Gemfile.lock", "bundle install"]
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_env_pre_steps (3.2)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local", "PRE_STEPS" => "rm Gemfile.lock && bundle install" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "test_env_pre_steps"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_automatic_retry_on
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_automatic_retry_on", retry_on: { limit: 1, exit_status: 127 }
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_automatic_retry_on (3.2)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 1, "exit_status" => 127 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "test_automatic_retry_on"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_soft_fail
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_soft_fail", soft_fail: true
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_soft_fail (3.2)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "soft_fail" => true,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "test_soft_fail"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_soft_fail_ruby
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), soft_fail: true)
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_soft_fail_ruby"
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_soft_fail_ruby (3.3)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-3"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-3-local" },
        "timeout_in_minutes" => 30,
        "soft_fail" => true,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "test_soft_fail_ruby"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_label_suffix
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "actionpack", label: "[rack-2]"
      end
    end

    expected = { "steps" =>
      [{ "label" => "actionpack (3.2) [rack-2]",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" =>
         { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
         [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
          { "artifacts#v1.0" =>
            { "download" =>
              [".buildkite/.empty",
               ".buildkite/docker-compose.yml",
               ".buildkite/Dockerfile",
               ".buildkite/Dockerfile.beanstalkd",
               ".buildkite/mysql-initdb.d",
               ".buildkite/runner"],
             "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
             "run" => "default",
             "pull" => "default",
             "config" => ".buildkite/docker-compose.yml",
             "shell" => ["runner", "actionpack"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_env_kwarg
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "actionpack", env: { RACK: "~> 2.0" }
      end
    end

    expected = { "steps" =>
      [{ "label" => "actionpack (3.2)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" =>
         { "IMAGE_NAME" => "buildkite-config-base:3-2-local",
           "RACK" => "~> 2.0" },
        "timeout_in_minutes" => 30,
        "plugins" =>
         [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
          { "artifacts#v1.0" =>
            { "download" =>
              [".buildkite/.empty",
               ".buildkite/docker-compose.yml",
               ".buildkite/Dockerfile",
               ".buildkite/Dockerfile.beanstalkd",
               ".buildkite/mysql-initdb.d",
               ".buildkite/runner"],
             "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
             "run" => "default",
             "pull" => "default",
             "config" => ".buildkite/docker-compose.yml",
             "shell" => ["runner", "actionpack"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_mysql_image_and_task_rails
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "activerecord", task: "mysql2:test"
      end
    end

    expected = { "steps" =>
      [{ "label" => "activerecord mysql2 (3.2)",
        "command" => ["rake db:mysql:rebuild mysql2:test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => ".dockerignore" } },
         { "artifacts#v1.0" =>
           { "download" =>
             [".buildkite/.empty",
              ".buildkite/docker-compose.yml",
              ".buildkite/Dockerfile",
              ".buildkite/Dockerfile.beanstalkd",
              ".buildkite/mysql-initdb.d",
              ".buildkite/runner"],
            "compressed" => ".buildkite.tgz" } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "activerecord"] } }] }] }
    assert_equal expected, pipeline.to_h
  end
end
