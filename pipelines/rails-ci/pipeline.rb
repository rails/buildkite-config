
require "pathname"
require "yaml"

LOCAL_BRANCH = ([ENV["BUILDKITE_BRANCH"], "main"] - [""]).first

BUILD_ID = ENV["BUILDKITE_BUILD_ID"]
REBUILD_ID = ([ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]] - [""]).first

MAINLINE = LOCAL_BRANCH == "main" || LOCAL_BRANCH =~ /\A[0-9-]+(?:-stable)?\z/

#REPO_ROOT = Pathname.new(ARGV.shift || File.expand_path("../..", __FILE__))
if %w[rails-ci rails-sandbox zzak/rails].include?(ENV["BUILDKITE_PIPELINE_NAME"])
  REPO_ROOT = Pathname.new(Dir.pwd)
else
  REPO_ROOT = Pathname.new(Dir.pwd) + "tmp/rails"
end

REPO_ROOT.join("rails.gemspec").read =~ /required_ruby_version[^0-9]+([0-9]+\.[0-9]+)/
RUBY_MINORS = %w(2.4 2.5 2.6 2.7 3.0 3.1 3.2).map { |v| Gem::Version.new(v) }
MIN_RUBY = Gem::Version.new($1 || "2.0")

RAILS_VERSION = Gem::Version.new(File.read(REPO_ROOT.join("RAILS_VERSION")))
BUNDLER =
  case RAILS_VERSION
  when Gem::Requirement.new("< 5.0")
    "< 2"
  when Gem::Requirement.new("< 6.1")
    "< 2.2.10"
  end
RUBYGEMS =
  case RAILS_VERSION
  when Gem::Requirement.new("< 5.0")
    "2.6.13"
  when Gem::Requirement.new("< 6.1")
    "3.2.9"
  end

MAX_RUBY =
  case RAILS_VERSION
  when Gem::Requirement.new("< 5.1")
    Gem::Version.new("2.4")
  when Gem::Requirement.new("< 5.2")
    Gem::Version.new("2.5")
  when Gem::Requirement.new("< 6.0")
    Gem::Version.new("2.6")
  when Gem::Requirement.new("< 6.1")
    Gem::Version.new("2.7")
  end


RUBIES = []
SOFT_FAIL = []

RUBY_MINORS.select { |v| v >= MIN_RUBY }.each do |v|
  image = "ruby:#{v}"

  if MAX_RUBY && v > MAX_RUBY && !(MAX_RUBY.approximate_recommendation === v)
    SOFT_FAIL << image
  else
    RUBIES << image
  end
end

MASTER_RUBY = "rubylang/ruby:master-nightly-jammy"
SOFT_FAIL << MASTER_RUBY

# Adds yjit: onto the master ruby image string so we
# know when to turn on YJIT via the environment variable.
# Same as master ruby, we want this to soft fail.
YJIT_RUBY = "yjit:#{MASTER_RUBY}"
SOFT_FAIL << YJIT_RUBY

# Run steps for newer Rubies first.
RUBIES.reverse!
SOFT_FAIL.reverse!

# Run soft-failing Ruby steps last.
RUBIES.concat SOFT_FAIL

BUILDKITE_ROOT_DIR = if ENV["CI"]
  Pathname.new(File.expand_path("../../.buildkite", __dir__))
else
  Pathname.new(File.expand_path("../../.buildkite", __dir__))
end

Buildkite::Builder.root(start_path: BUILDKITE_ROOT_DIR)
Buildkite::Builder.pipeline do
  require_relative "../../lib/buildkite_config"

  use Buildkite::Config::DockerBuild
  use Buildkite::Config::DockerCompose
  use Buildkite::Config::RubyGroup

  group do
    label "build"
    (RUBIES - [YJIT_RUBY]).map do |ruby|
      builder ruby: ruby do
        env["BUNDLER"] = BUNDLER
        env["RUBYGEMS"] = RUBYGEMS
      end
    end
  end

  RUBIES.each do |ruby|
    ruby_group ruby do
      # GROUP 1: Runs additional isolated tests for non-PR builds
      %w(
        actionpack      test                default
        actionmailer    test                default
        activemodel     test                default
        activesupport   test                default
        actionview      test                default
        activejob       test                default
        activerecord    mysql2:test         mysqldb
        activerecord    trilogy:test        mysqldb
        activerecord    postgresql:test     postgresdb
        activerecord    sqlite3:test        default
      ).each_slice(3) do |dir, task, service|
        next if RAILS_VERSION < Gem::Version.new("7.1.0.alpha") && task == "trilogy:test"

        compose subdirectory: dir, rake_task: task, ruby: pipeline.data.ruby, service: service

        next unless MAINLINE

        if dir == "activerecord"
          compose subdirectory: dir, rake_task: task.sub(":test", ":isolated_test"), ruby: ruby, service: service do
            parallelism 5 if REPO_ROOT.join("activerecord/Rakefile").read.include?("BUILDKITE_PARALLEL")
          end
        elsif dir == "actiontext"
          # added during 7.1 development on main
          if REPO_ROOT.join("actiontext/Rakefile").read.include?("task :isolated")
            compose subdirectory: dir, rake_task: "#{task}:isolated", ruby: ruby, service: service
          end
        else
          compose subdirectory: dir, rake_task: "#{task}:isolated", ruby: ruby, service: service
        end
      end

      # GROUP 2: No isolated tests, runs for each supported ruby
      %w(
        actioncable     test                postgresdb
        activestorage   test                default
        actionmailbox   test                default
        guides          test                default
      ).each_slice(3) do |dir, task, service|
        compose subdirectory: dir, rake_task: task, ruby: ruby, service: service
      end

      # GROUP 3: Special cases

      if RAILS_VERSION >= Gem::Version.new("5.1.x")
        compose subdirectory: "activerecord", rake_task: "sqlite3_mem:test", ruby: ruby, service: "default"
      end
      if RAILS_VERSION >= Gem::Version.new("6.1.x")
        compose subdirectory: "activerecord", rake_task: "mysql2:test", ruby: ruby, service: "mysqldb" do |attrs|
          label "#{attrs["label"]} [prepared_statements]"
          env["MYSQL_PREPARED_STATEMENTS"] = "true"
        end
      end
      compose subdirectory: "activerecord", rake_task: "mysql2:test", ruby: ruby, service: "mysqldb" do |attrs|
        label "#{attrs["label"]} [mysql_5_7]"
        env["MYSQL_IMAGE"] = "mysql:5.7"
      end
      if RAILS_VERSION >= Gem::Version.new("7.1.0.alpha")
        compose subdirectory: "activerecord", rake_task: "trilogy:test", ruby: ruby, service: "mysqldb" do |attrs|
          label "#{attrs["label"]} [mysql_5_7]"
          env["MYSQL_IMAGE"] = "mysql:5.7"
        end
      end
      if RAILS_VERSION >= Gem::Version.new("5.x")
        compose subdirectory: "activerecord", rake_task: "mysql2:test", ruby: ruby, service: "mysqldb" do |attrs|
          label "#{attrs["label"]} [mariadb]"
          env["MYSQL_IMAGE"] =
            if RAILS_VERSION < Gem::Version.new("6.x")
              "mariadb:10.2"
            else
              "mariadb:latest"
            end
        end
      end
      if RAILS_VERSION >= Gem::Version.new("7.1.0.alpha")
        compose subdirectory: "activerecord", rake_task: "trilogy:test", ruby: ruby, service: "mysqldb" do |attrs|
          label "#{attrs["label"]} [mariadb]"
          env["MYSQL_IMAGE"] = "mariadb:latest"
        end
      end
      compose subdirectory: "actioncache", rake_task: "test:integration", ruby: ruby, service: "default" do |attrs|
        if RAILS_VERSION < Gem::Version.new("6.x")
          soft_fail true
        else
          attrs["retry"] = nil
          automatic_retry_on exit_status: -1, limit: 3
        end
      end
      if REPO_ROOT.join("actionview/Rakefile").read.include?("task :ujs")
        compose subdirectory: "actionview", rake_task: "test:ujs", ruby: ruby, service: "actionview" do |attrs|
          attrs["retry"] = nil
          automatic_retry_on exit_status: -1, limit: 3
        end
      end
      compose subdirectory: "activejob", rake_task: "test:integration", ruby: ruby, service: "activejob" do
        # Enable soft_fail until the problem in queue_classic is solved.
        # https://github.com/rails/rails/pull/37517#issuecomment-545370408
        soft_fail true # if RAILS_VERSION < Gem::Version.new("5.x")
      end
      compose subdirectory: "railties", rake_task: "test", ruby: ruby, service: "railties" do
        parallelism = 12 if REPO_ROOT.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
      end

      compose subdirectory: "actionpack", rake_task: "test", ruby: ruby, service: "default", pre_steps: ["bundle install"] do |attrs|
        label "#{attrs["label"]} [rack-2]"
        env["RACK"] = "~> 2.0"
      end

      compose subdirectory: "railties", rake_task: "test", ruby: ruby, service: "railties", pre_steps: ["bundle install"] do |attrs|
        parallelism = 12 if REPO_ROOT.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
        label "#{attrs["label"]} [rack-2]"
        env["RACK"] = "~> 2.0"
      end

      compose subdirectory: "actionpack", rake_task: "test", ruby: ruby, service: "default", pre_steps: ["rm Gemfile.lock", "bundle install"] do |attrs|
        label "#{attrs["label"]} [rack-head]"
        env["RACK"] = "head"
        soft_fail true
      end

      compose subdirectory: "railties", rake_task: "test", ruby: ruby, service: "railties", pre_steps: ["rm Gemfile.lock", "bundle install"] do |attrs|
        parallelism = 12 if REPO_ROOT.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
        label "#{attrs["label"]} [rack-head]"
        env["RACK"] = "head"
        soft_fail true
      end
    end
  end
end