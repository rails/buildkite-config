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

    expected = { "steps" => [{ "depends_on" => ["rubylang/ruby:master"] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_rake_command
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_equal 1, pipeline.to_h["steps"].size
    assert_includes pipeline.to_h["steps"][0], "command"
    assert_equal "rake test:all", pipeline.to_h["steps"][0]["command"][0]
  end

  def test_default_task
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "activerecord"
      end
    end

    assert_equal 1, pipeline.to_h["steps"].size
    assert_includes pipeline.to_h["steps"][0], "command"
    assert_equal "rake test", pipeline.to_h["steps"][0]["command"][0]
  end

  def test_depends_on
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "depends_on"
    assert_equal "docker-image-ruby-3-2", pipeline.to_h["steps"][0]["depends_on"][0]
  end

  def test_artifact_paths
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "artifact_paths"
    assert_equal ["test-reports/*/*.xml"], pipeline.to_h["steps"][0]["artifact_paths"]
  end

  def test_agents
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "agents"
    assert_equal({ "queue" => "default" }, pipeline.to_h["steps"][0]["agents"])
  end

  def test_retry
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "retry"
    assert_equal({ "automatic" => [{ "limit" => 2, "exit_status" => -1 }, { "limit" => 2, "exit_status" => 255 }] }, pipeline.to_h["steps"][0]["retry"])
  end

  def test_env
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "env"
    assert_includes pipeline.to_h["steps"][0]["env"], "IMAGE_NAME"
    assert_equal "buildkite-config-base:ruby-3-2-local", pipeline.to_h["steps"][0]["env"]["IMAGE_NAME"]
  end

  def test_timeout_in_minutes
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "timeout_in_minutes"
    assert_equal 30, pipeline.to_h["steps"][0]["timeout_in_minutes"]
  end

  def test_artifacts
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "plugins"
    plugins = pipeline.to_h["steps"][0]["plugins"]

    artifacts = plugins.select { |plugin|
      plugin.key?(plugins_map[:artifacts])
    }
    assert_equal ".dockerignore", artifacts[0][plugins_map[:artifacts]]["download"]

    download = artifacts[1][plugins_map[:artifacts]]
    assert_equal %w[
      .buildkite/.empty
      .buildkite/docker-compose.yml
      .buildkite/Dockerfile
      .buildkite/Dockerfile.beanstalkd
      .buildkite/mysql-initdb.d
      .buildkite/runner
    ], download["download"]
    assert_equal ".buildkite.tgz", download["compressed"]
  end

  def test_compose_hosted
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV["BUILDKITE_COMPUTE_TYPE"] = "hosted"

    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    plugins = pipeline.to_h["steps"][0]["plugins"]

    compose = plugins.find { |plugin|
      plugin.key?(plugins_map[:compose])
    }.fetch(plugins_map[:compose])

    %w[env run config shell tty].each do |key|
      assert_includes compose, key
    end

    assert_includes compose["env"], "PRE_STEPS"
    assert_includes compose["env"], "RACK"

    assert_equal "default", compose["run"]
    assert_equal "true", compose["tty"]
    assert_equal ".buildkite/docker-compose.yml", compose["config"]
    assert_equal ["runner", "test"], compose["shell"]
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
  end

  def test_compose_self_hosted
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV["BUILDKITE_COMPUTE_TYPE"] = "self-hosted"

    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test", task: "test:all"
      end
    end

    plugins = pipeline.to_h["steps"][0]["plugins"]

    compose = plugins.find { |plugin|
      plugin.key?(plugins_map[:compose])
    }.fetch(plugins_map[:compose])

    %w[env run pull config shell].each do |key|
      assert_includes compose, key
    end

    assert_includes compose["env"], "PRE_STEPS"
    assert_includes compose["env"], "RACK"

    assert_equal "default", compose["run"]
    assert_equal "default", compose["pull"]
    assert_equal ".buildkite/docker-compose.yml", compose["config"]
    assert_equal ["runner", "test"], compose["shell"]
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
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

    assert_equal 2, pipeline.to_h["steps"].size
    ["first all (3.2)", "second all (3.2)"].each_with_index do |label, index|
      assert_equal label, pipeline.to_h["steps"][index]["label"]
    end

    ["first", "second"].each_with_index do |task, index|
      plugins = pipeline.to_h["steps"][index]["plugins"]

      compose = plugins.find { |plugin|
        plugin.key?(plugins_map[:compose])
      }.fetch(plugins_map[:compose])

      assert_equal "default", compose["run"]
    end
  end

  def test_docker_compose_plugin_service
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "subdirectory", service: "myservice"
      end
    end

    plugins = pipeline.to_h["steps"][0]["plugins"]

    compose = plugins.find { |plugin|
      plugin.key?(plugins_map[:compose])
    }.fetch(plugins_map[:compose])

    %w[run].each do |key|
      assert_includes compose, key
    end

    assert_equal "myservice", compose["run"]
  end

  def test_env_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RakeCommand

      build_context.ruby = Buildkite::Config::RubyConfig.yjit_ruby
      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_env_yjit"
      end
    end

    yjit = Buildkite::Config::RubyConfig.yjit_ruby

    assert_equal 1, pipeline.to_h["steps"].size
    assert_equal "test_env_yjit (yjit)", pipeline.to_h["steps"][0]["label"]
    assert_equal "docker-image-#{yjit.image_key}", pipeline.to_h["steps"][0]["depends_on"][0]

    assert_equal "buildkite-config-base:#{yjit.image_name_for("local")}", pipeline.to_h["steps"][0]["env"]["IMAGE_NAME"]

    assert_includes pipeline.to_h["steps"][0]["env"], "RUBY_YJIT_ENABLE"
    assert_equal "1", pipeline.to_h["steps"][0]["env"]["RUBY_YJIT_ENABLE"]

    assert_not_includes pipeline.to_h["steps"][0], "soft_fail"
  end

  def test_env_pre_steps
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_env_pre_steps", pre_steps: ["rm Gemfile.lock", "bundle install"]
      end
    end

    assert_includes pipeline.to_h["steps"][0]["env"], "PRE_STEPS"
    assert_equal "rm Gemfile.lock && bundle install", pipeline.to_h["steps"][0]["env"]["PRE_STEPS"]

    plugins = pipeline.to_h["steps"][0]["plugins"]

    compose = plugins.find { |plugin|
      plugin.key?(plugins_map[:compose])
    }.fetch(plugins_map[:compose])

    assert_includes compose["env"], "PRE_STEPS"
  end

  def test_automatic_retry_on
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_automatic_retry_on", retry_on: { limit: 1, exit_status: 127 }
      end
    end

    assert_includes pipeline.to_h["steps"][0], "retry"
    assert_equal({ "automatic" => [{ "limit" => 1, "exit_status" => 127 }] }, pipeline.to_h["steps"][0]["retry"])
  end

  def test_soft_fail
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_soft_fail", soft_fail: true
      end
    end

    assert_includes pipeline.to_h["steps"][0], "soft_fail"
    assert_equal true, pipeline.to_h["steps"][0]["soft_fail"]
  end

  def test_soft_fail_ruby
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), soft_fail: true)
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "test_soft_fail_ruby"
      end
    end

    assert_includes pipeline.to_h["steps"][0], "soft_fail"
    assert_equal true, pipeline.to_h["steps"][0]["soft_fail"]
  end

  def test_rake_label_suffix
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "actionpack", label: "[rack-2]"
      end
    end


    assert_includes pipeline.to_h["steps"][0], "label"
    assert_equal "actionpack (3.2) [rack-2]", pipeline.to_h["steps"][0]["label"]
  end

  def test_rake_env_kwarg
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "actionpack", env: { RACK: "~> 2.0" }
      end
    end

    assert_includes pipeline.to_h["steps"][0], "env"
    assert_equal "~> 2.0", pipeline.to_h["steps"][0]["env"]["RACK"]

    plugins = pipeline.to_h["steps"][0]["plugins"]

    compose = plugins.find { |plugin|
      plugin.key?(plugins_map[:compose])
    }.fetch(plugins_map[:compose])

    assert_includes compose["env"], "RACK"
  end

  def test_rake_mysql_image_and_task_rails
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      build_context.stub(:rails_version, Gem::Version.new("7.1")) do
        rake "activerecord", task: "mysql2:test"
      end
    end

    assert_equal "activerecord mysql2 (3.2)", pipeline.to_h["steps"][0]["label"]
    assert_equal ["rake db:mysql:rebuild mysql2:test"], pipeline.to_h["steps"][0]["command"]
  end

  def test_bundle_command
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.2"))
      use Buildkite::Config::RakeCommand

      bundle "rubocop", label: "rubocop"
    end

    assert_equal 1, pipeline.to_h["steps"].size

    step = pipeline.to_h["steps"][0]

    assert_equal "rubocop", step["label"]
    assert_equal "docker-image-ruby-3-2", step["depends_on"][0]
    assert_includes step, "command"
    assert_equal "rubocop", step["command"][0]

    plugins = step["plugins"]

    assert_equal 3, plugins.size

    artifacts = plugins[0]

    assert_equal plugins_map[:artifacts], artifacts.keys.first
    assert_equal ".dockerignore", artifacts[plugins_map[:artifacts]]["download"]

    artifacts = plugins[1]

    assert_equal plugins_map[:artifacts], artifacts.keys.first
    assert_equal %w[
      .buildkite/.empty
      .buildkite/docker-compose.yml
      .buildkite/Dockerfile
      .buildkite/Dockerfile.beanstalkd
      .buildkite/mysql-initdb.d
      .buildkite/runner
    ], artifacts[plugins_map[:artifacts]]["download"]
    assert_equal ".buildkite.tgz", artifacts[plugins_map[:artifacts]]["compressed"]

    compose = plugins[2].fetch(plugins_map[:compose])

    assert_not_includes compose, "env"
    assert_equal "default", compose["run"]
    assert_equal ".buildkite/docker-compose.yml", compose["config"]
    assert_equal ["runner", "."], compose["shell"]

    assert_equal "buildkite-config-base:ruby-3-2-local", step["env"]["IMAGE_NAME"]
    assert_equal "default", step["agents"]["queue"]
    assert_equal ["test-reports/*/*.xml"], step["artifact_paths"]
    assert_equal 30, step["timeout_in_minutes"]
  end
end
