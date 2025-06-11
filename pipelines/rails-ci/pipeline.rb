# frozen_string_literal: true

Buildkite::Builder.pipeline do
  require "buildkite_config"
  use Buildkite::Config::BuildContext
  use Buildkite::Config::DockerBuild
  use Buildkite::Config::RakeCommand
  use Buildkite::Config::RubyGroup

  plugin :docker_compose, "docker-compose#v4.16.0"
  plugin :artifacts, "artifacts#v1.9.3"

  if build_context.nightly?
    build_context.rubies << Buildkite::Config::RubyConfig.master_ruby
    build_context.rubies << Buildkite::Config::RubyConfig.yjit_ruby
    build_context.rubies << Buildkite::Config::RubyConfig.master_debug_ruby
    build_context.default_ruby = Buildkite::Config::RubyConfig.master_ruby
  else
    build_context.setup_rubies %w(2.4 2.5 2.6 2.7 3.0 3.1 3.2 3.3 3.4)
  end

  group do
    label "build"
    build_context.rubies.each do |ruby|
      builder ruby
    end
  end

  # Lints
  ruby_group build_context.default_ruby do
    label "lint"

    bundle "rubocop --parallel", label: "rubocop"

    if build_context.support_guides_lint?
      rake "guides", task: "guides:lint"
    end

    if build_context.has_railspect?
      bundle "tools/railspect changelogs .", label: "changelogs"
      bundle "tools/railspect configuration .", label: "configuration"
    end
  end

  if build_context.skip?
    command do
      label ":bk-status-passed: Build skipped"
      skip true
      command "true"
    end

    next
  end

  build_context.rubies.each do |ruby|
    ruby_group ruby do
      rake "actioncable",
        service: "postgresdb",
        pre_steps: ["bundle exec rake -f activerecord/Rakefile db:postgresql:rebuild"]
      rake "actionmailbox"
      rake "actionmailer"
      rake "actionpack"

      if build_context.test_with_multiple_versions_of_rack?(ruby)
        rake "actionpack",
          pre_steps: ["bundle install"],
          label: "[rack-2]",
          env: { RACK: "~> 2.0" }

        rake "actionpack",
          pre_steps: ["bundle install"],
          label: "[rack-3-0]",
          env: { RACK: "~> 3.0.0" }

        rake "actionpack",
          pre_steps: ["rm Gemfile.lock", "bundle install"],
          label: "[rack-head]",
          env: { RACK: "head" },
          soft_fail: true
      end

      rake "actiontext"
      rake "actionview"
      rake "activejob"
      rake "activemodel"

      rake "activerecord", task: "mysql2:test", service: "mysqldb"

      if ruby == build_context.default_ruby
        rake "activerecord", task: "mysql2:test",
          service: "mariadb",
          label: "[mariadb]",
          env: { MYSQL_IMAGE: "mariadb:11.4" }

        rake "activerecord", task: "mysql2:test",
          service: "mysqldb",
          label: "[mysql_5_7]",
          env: { MYSQL_IMAGE: "mysql:5.7" }

        if build_context.rails_version >= Gem::Version.new("6.1.x")
          rake "activerecord", task: "mysql2:test",
            service: "mysqldb",
            label: "[prepared_statements]",
            env: { MYSQL_PREPARED_STATEMENTS: "true" }
        end
      end

      rake "activerecord", task: "postgresql:test", service: "postgresdb"
      rake "activerecord", task: "sqlite3:test"

      if ruby == build_context.default_ruby
        rake "activerecord", task: "sqlite3_mem:test"
      end

      if build_context.supports_trilogy?
        rake "activerecord", task: "trilogy:test", service: "mysqldb"

        if ruby == build_context.default_ruby
          rake "activerecord", task: "trilogy:test",
            service: "mariadb",
            label: "[mariadb]",
            env: { MYSQL_IMAGE: "mariadb:11.4" }

          rake "activerecord", task: "trilogy:test",
            service: "mysqldb",
            label: "[mysql_5_7]",
            env: { MYSQL_IMAGE: "mysql:5.7" }
        end
      end

      rake "activestorage"
      rake "activesupport"
      rake "guides"

      rake "railties", service: "railties", parallelism: 12

      if build_context.test_with_multiple_versions_of_rack?(ruby)
        rake "railties",
          service: "railties",
          pre_steps: ["bundle install"],
          parallelism: 12,
          label: "[rack-2]",
          env: { RACK: "~> 2.0" }

        rake "railties",
          service: "railties",
          pre_steps: ["bundle install"],
          parallelism: 12,
          label: "[rack-3-0]",
          env: { RACK: "~> 3.0.0" }

        rake "railties",
          service: "railties",
          pre_steps: ["rm Gemfile.lock", "bundle install"],
          parallelism: 12,
          label: "[rack-head]",
          env: { RACK: "head" },
          soft_fail: true
      end

      # ActionCable and ActiveJob integration tests
      rake "actioncable", task: "test:integration", retry_on: { exit_status: -1, limit: 3 }

      if ruby == build_context.default_ruby
        if build_context.rails_root.join("actionview/Rakefile").read.include?("task :ujs")
          rake "actionview", task: "test:ujs", service: "actionview", retry_on: { exit_status: -1, limit: 3 }
        end
      end

      rake "activejob", task: "test:integration",
        service: "activejob",
        # Enable soft_fail until the problem in queue_classic is solved.
        # https://github.com/rails/rails/pull/37517#issuecomment-545370408
        soft_fail: true
    end
  end

  # Isolated tests
  ruby_group build_context.default_ruby do
    label "isolated"

    rake "activerecord", task: "mysql2:isolated_test", service: "mysqldb", parallelism: 5
    rake "activerecord", task: "postgresql:isolated_test", service: "postgresdb", parallelism: 5
    rake "activerecord", task: "sqlite3:isolated_test", parallelism: 5

    if build_context.supports_trilogy?
      rake "activerecord", task: "trilogy:isolated_test",
        service: "mysqldb", parallelism: 5
    end

    rake "actionmailer", task: "test:isolated"
    rake "actionpack", task: "test:isolated"
    rake "actionview", task: "test:isolated"
    rake "activejob", task: "test:isolated"
    rake "activemodel", task: "test:isolated"
    rake "activesupport", task: "test:isolated"
  end
end
