# frozen_string_literal: true

require "pathname"
require "yaml"

BUILDKITE_ROOT_DIR = if ENV["CI"]
  Buildkite::Builder.root.join(".buildkite")
else
  Buildkite::Builder.root
end

$LOAD_PATH.unshift(BUILDKITE_ROOT_DIR.join("lib").to_s)

Buildkite::Builder.pipeline do
  require "buildkite_config"

  use Buildkite::Config::BuildContext
  use Buildkite::Config::DockerBuild
  use Buildkite::Config::RakeCommand
  use Buildkite::Config::RubyGroup

  plugin :docker_compose, "docker-compose#v3.7.0"
  # plugin :docker_compose, "docker-compose#v4.16.0"
  plugin :artifacts, "artifacts#v1.2.0"
  # plugin :artifacts, "artifacts#v1.9.2"

  build_context.rubies << Buildkite::Config::RubyConfig.master_ruby
  build_context.rubies << Buildkite::Config::RubyConfig.yjit_ruby
  build_context.rubies << Buildkite::Config::RubyConfig.master_debug_ruby
  build_context.default_ruby = Buildkite::Config::RubyConfig.master_ruby

  group do
    label "build"
    build_context.rubies.each do |ruby|
      builder ruby: ruby
    end
  end

  build_context.rubies.each do |ruby|
    ruby_group config: ruby do
      rake "actioncable", service: "postgresdb", pre_steps: ["bundle exec rake -f activerecord/Rakefile db:postgresql:rebuild"]
      rake "actionmailbox"
      rake "actionmailer"
      rake "actionpack"

      if ruby == build_context.default_ruby
        rake "actionpack", pre_steps: ["bundle install"] do |attrs, _|
          label "#{attrs["label"]} [rack-2]"
          env["RACK"] = "~> 2.0"
        end
        rake "actionpack", pre_steps: ["rm Gemfile.lock", "bundle install"] do |attrs, _|
          label "#{attrs["label"]} [rack-head]"
          env["RACK"] = "head"
          soft_fail true
        end
      end

      rake "actiontext"
      rake "actionview"
      rake "activejob"
      rake "activemodel"

      rake "activerecord", "mysql2:test", service: "mysqldb"

      if ruby == build_context.default_ruby
        if build_context.rails_version >= Gem::Version.new("5.x")
          rake "activerecord", "mysql2:test", service: "mariadb" do |attrs, build_context|
            label "#{attrs["label"]} [mariadb]"
            env["MYSQL_IMAGE"] =
              if build_context.rails_version < Gem::Version.new("6.x")
                "mariadb:10.2"
              else
                "mariadb:latest"
              end
          end
        end

        rake "activerecord", "mysql2:test", service: "mysqldb" do |attrs, _|
          label "#{attrs["label"]} [mysql_5_7]"
          env["MYSQL_IMAGE"] = "mysql:5.7"
        end

        if build_context.rails_version >= Gem::Version.new("6.1.x")
          rake "activerecord", "mysql2:test", service: "mysqldb" do |attrs, _|
            label "#{attrs["label"]} [prepared_statements]"
            env["MYSQL_PREPARED_STATEMENTS"] = "true"
          end
        end
      end

      rake "activerecord", "postgresql:test", service: "postgresdb"
      rake "activerecord", "sqlite3:test"

      if ruby == build_context.default_ruby && build_context.rails_version >= Gem::Version.new("5.1.x")
        rake "activerecord", "sqlite3_mem:test"
      end

      if build_context.rails_version >= Gem::Version.new("7.1.0.alpha")
        rake "activerecord", "trilogy:test", service: "mysqldb"

        if ruby == build_context.default_ruby
          rake "activerecord", "trilogy:test", service: "mariadb" do |attrs, _|
            label "#{attrs["label"]} [mariadb]"
            env["MYSQL_IMAGE"] = "mariadb:latest"
          end

          rake "activerecord", "trilogy:test", service: "mysqldb" do |attrs, _|
            label "#{attrs["label"]} [mysql_5_7]"
            env["MYSQL_IMAGE"] = "mysql:5.7"
          end
        end
      end

      rake "activestorage"
      rake "activesupport"
      rake "guides"

      rake "railties", service: "railties" do |_, build_context|
        parallelism 12 if build_context.rails_root.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
      end

      if ruby == build_context.default_ruby
        rake "railties", service: "railties", pre_steps: ["bundle install"] do |attrs, build_context|
          parallelism 12 if build_context.rails_root.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
          label "#{attrs["label"]} [rack-2]"
          env["RACK"] = "~> 2.0"
        end

        rake "railties", service: "railties", pre_steps: ["rm Gemfile.lock", "bundle install"] do |attrs, build_context|
          parallelism 12 if build_context.rails_root.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
          label "#{attrs["label"]} [rack-head]"
          env["RACK"] = "head"
          soft_fail true
        end
      end

      # ActionCable and ActiveJob integration tests
      rake "actioncable", "test:integration" do |attrs, build_context|
        if build_context.rails_version < Gem::Version.new("6.x")
          soft_fail true
        else
          attrs["retry"] = nil
          automatic_retry_on exit_status: -1, limit: 3
        end
      end

      if ruby == build_context.default_ruby
        if build_context.rails_root.join("actionview/Rakefile").read.include?("task :ujs")
          rake "actionview", "test:ujs", service: "actionview" do |attrs, _|
            attrs["retry"] = nil
            automatic_retry_on exit_status: -1, limit: 3
          end
        end
      end

      rake "activejob", "test:integration", service: "activejob" do |attrs, build_context|
        # Enable soft_fail until the problem in queue_classic is solved.
        # https://github.com/rails/rails/pull/37517#issuecomment-545370408
        soft_fail true if build_context.rails_version < Gem::Version.new("5.x")
      end
    end
  end

  # Isolated tests
  ruby_group config: build_context.default_ruby do
    label "isolated"

    isolated_db_tasks = %w(
      activerecord    mysql2:isolated_test       mysqldb
      activerecord    postgresql:isolated_test   postgresdb
      activerecord    sqlite3:isolated_test      default
    )

    if build_context.rails_version >= Gem::Version.new("7.1.0.alpha")
      isolated_db_tasks << "activerecord" << "trilogy:isolated_test" << "mysqldb"
    end

    isolated_db_tasks.each_slice(3) do |dir, task, service|
      rake dir, task, service: service do |_, build_context|
        parallelism 5 if build_context.rails_root.join("activerecord/Rakefile").read.include?("BUILDKITE_PARALLEL")
      end
    end

    %w(
      actionmailer    test:isolated
      actionpack      test:isolated
      actionview      test:isolated
      activejob       test:isolated
      activemodel     test:isolated
      activesupport   test:isolated
    ).each_slice(2) do |dir, task|
      rake dir, task
    end
  end
end
