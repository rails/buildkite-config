# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestRakeCommand < TestCase
  def test_to_label
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))

      group do
        label to_label(ruby, "test", "test:all")
      end
    end

    expected = { "steps" => [{ "label" => "test all (3.2)", "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_ruby_image_key
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: "3.2", prefix: "ruby:")

      group do
        depends_on build_context.ruby.image_key
      end
    end

    expected = { "steps" => [{ "depends_on" => ["ruby-3-2"], "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_depends_on_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand
      build_context.ruby = Buildkite::Config::RubyConfig.yjit_ruby

      group do
        depends_on build_context.ruby.ruby_image
      end
    end

    expected = { "steps" => [{ "depends_on" => ["rubylang/ruby:master-nightly-jammy"], "group" => nil, "steps" => [] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_command
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", "test:all"
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
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
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
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
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
        rake "first", "test:all"
        rake "second", "test:all"
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
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
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
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
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
        rake "subdirectory", "test:isolated", service: "myservice"
      end
    end

    expected = { "steps" =>
      [{ "label" => "subdirectory isolated (3.2)",
        "command" => ["rake test:isolated"],
        "depends_on" => ["docker-image-3-2"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "artifact_paths" => ["test-reports/*/*.xml"],
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
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
        rake
      end
    end

    expected = { "steps" =>
      [{ "label" => " (yjit)",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-rubylang-ruby-master-nightly-jammy"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:rubylang-ruby-master-nightly-jammy-local", "RUBY_YJIT_ENABLE" => "1" },
        "soft_fail" => true,
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_env_pre_steps
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake pre_steps: ["rm Gemfile.lock", "bundle install"] do
          label "test_env_pre_steps"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_env_pre_steps",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local", "PRE_STEPS" => "rm Gemfile.lock && bundle install" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_agents
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake do
          label "test_agents"
          agents queue: "test_agents"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_agents",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "test_agents" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_artifact_paths
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake do
          label "test_artifact_paths"
          artifact_paths ["test_artifact_paths"]
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_artifact_paths",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test_artifact_paths"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_automatic_retry_on
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake do |attrs, _|
          label "test_automatic_retry_on"
          # Reset "automatic_retry_on" from the default
          # Since this does a push, and we only want a single value, I think.
          attrs["retry"] = nil
          automatic_retry_on limit: 1, exit_status: 127
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_automatic_retry_on",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 1, "exit_status" => 127 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_timeout_in_minutes
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake do
          label "test_timeout_in_minutes"
          timeout_in_minutes 10
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_timeout_in_minutes",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 10,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_soft_fail
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake do
          label "soft_fail"
          soft_fail true
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "soft_fail",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local" },
        "timeout_in_minutes" => 30,
        "soft_fail" => true,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_soft_fail_ruby
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), soft_fail: true)
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake do
          label "test_soft_fail_ruby"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "test_soft_fail_ruby",
        "command" => ["rake test"],
        "depends_on" => ["docker-image-3-3"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-3-local" },
        "timeout_in_minutes" => 30,
        "soft_fail" => true,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", ""] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_with_block
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", "all" do |attrs, _|
          label "#{attrs["label"]} with_block"
          env["MYSQL_IMAGE"] = "mariadb:latest"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "test all (3.2) with_block",
        "command" => ["rake all"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local", "MYSQL_IMAGE" => "mariadb:latest" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "test"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_mysql_image_and_task_rails
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "activerecord", "mysql2:test"
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
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "default",
            "pull" => "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "activerecord"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_mysql_image_and_task_rails_5_x
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("5.1")) do
        rake "activerecord", "mysql2:test", service: "mysqldb"
      end
    end

    expected = { "steps" =>
      [{ "label" => "activerecord mysql2 (3.2)",
        "command" => ["rake db:mysql:rebuild mysql2:test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local",
                   "MYSQL_IMAGE" => "mysql:5.7",
                   "POSTGRES_IMAGE" => "postgres:9.6-alpine" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "mysqldb",
            "pull" => "mysqldb",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "activerecord"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_mysql_image_and_task_rails_4_x
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("4.2")) do
        rake "activerecord", "mysql2:test", service: "mysqldb"
      end
    end

    expected = { "steps" =>
      [{ "label" => "activerecord mysql2 (3.2)",
        "command" => ["rake db:mysql:rebuild mysql2:test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local",
                   "MYSQL_IMAGE" => "mysql:5.6",
                   "POSTGRES_IMAGE" => "postgres:9.6-alpine" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "mysqldb",
            "pull" => "mysqldb",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "activerecord"] } }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_postgres_image_and_task_rails_5_1
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("5.1")) do
        rake "activerecord", "postgresql:test", service: "postgresdb"
      end
    end

    expected = { "steps" =>
      [{ "label" => "activerecord postgresql (3.2)",
        "command" => ["rake db:postgresql:rebuild postgresql:test"],
        "depends_on" => ["docker-image-3-2"],
        "artifact_paths" => ["test-reports/*/*.xml"],
        "agents" => { "queue" => "default" },
        "retry" => { "automatic" => [{ "limit" => 2, "exit_status" => -1 }] },
        "env" => { "IMAGE_NAME" => "buildkite-config-base:3-2-local",
                   "MYSQL_IMAGE" => "mysql:5.7",
                   "POSTGRES_IMAGE" => "postgres:9.6-alpine" },
        "timeout_in_minutes" => 30,
        "plugins" =>
        [{ "artifacts#v1.0" => { "download" => [".buildkite/*", ".buildkite/**/*"] } },
          { "docker-compose#v1.0" =>
            { "env" => ["PRE_STEPS", "RACK"],
            "run" => "postgresdb",
            "pull" => "postgresdb",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", "activerecord"] } }] }] }
    assert_equal expected, pipeline.to_h
  end
end
