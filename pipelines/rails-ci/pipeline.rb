
require "json"
require "net/http"
require "pathname"
require "yaml"

STANDARD_QUEUES = [nil, "default", "builder"]

# If the pipeline is running in a non-standard queue, default to
# running everything in that queue.
unless STANDARD_QUEUES.include?(ENV["BUILDKITE_AGENT_META_DATA_QUEUE"])
  ENV["QUEUE"] ||= ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
end

BUILD_QUEUE = ENV["BUILD_QUEUE"] || ENV["QUEUE"] || "builder"
RUN_QUEUE = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"

IMAGE_BASE = ENV["DOCKER_IMAGE"] || "973266071021.dkr.ecr.us-east-1.amazonaws.com/#{"#{BUILD_QUEUE}-" unless STANDARD_QUEUES.include?(BUILD_QUEUE)}builds"

BASE_BRANCH = ([ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"], ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
LOCAL_BRANCH = ([ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
PULL_REQUEST = ([ENV["BUILDKITE_PULL_REQUEST"]] - ["false"]).first

BUILD_ID = ENV["BUILDKITE_BUILD_ID"]
REBUILD_ID = ([ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]] - [""]).first

MAINLINE = LOCAL_BRANCH == "main" || LOCAL_BRANCH =~ /\A[0-9-]+(?:-stable)?\z/

DOCKER_COMPOSE_PLUGIN = "docker-compose#v3.7.0"
ARTIFACTS_PLUGIN = "artifacts#v1.2.0"

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

ONE_RUBY = RUBIES.last || SOFT_FAIL.last

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

STEPS = []

def image_name_for(ruby, suffix = BUILD_ID, short: false)
  ruby = ruby_image(ruby)

  tag = "#{mangle_name(ruby)}-#{suffix}"

  if short
    tag
  else
    "#{IMAGE_BASE}:#{tag}"
  end
end

def mangle_name(name)
  name.tr("^A-Za-z0-9", "-")
end

# YJIT uses the same image as ruby-trunk because it's turned on
# via an ENV var. This needs to remove the `yjit:` added onto the
# front because otherwise it's not a valid image.
def ruby_image(ruby)
  if ruby == YJIT_RUBY
    ruby.sub("yjit:", "")
  else
    ruby
  end
end

# A shortened version of the name for the Buildkite label.
def short_ruby(ruby)
  if ruby == MASTER_RUBY
    "master"
  elsif ruby == YJIT_RUBY
    "yjit"
  else
    ruby.sub(/^ruby:|:latest$/, "")
  end
end

def step_for(subdirectory, rake_task, ruby: nil, service: "default", pre_steps: [])
  return unless REPO_ROOT.join(subdirectory).exist?

  label = +"#{subdirectory} #{rake_task.sub(/[:_]test|test:/, "")}"
  label.sub!(/ test/, "")
  if ruby
    label << " (#{short_ruby(ruby)})"
  end

  if rake_task.start_with?("mysql2:") || (RAILS_VERSION >= Gem::Version.new("7.1.0.alpha") && rake_task.start_with?("trilogy:"))
    rake_task = "db:mysql:rebuild #{rake_task}"
  elsif rake_task.start_with?("postgresql:")
    rake_task = "db:postgresql:rebuild #{rake_task}"
  end

  env = {
    "IMAGE_NAME" => image_name_for(ruby || ONE_RUBY),
  }

  # If we have YJIT_RUBY set the environment variable
  # to turn it on.
  if ruby == YJIT_RUBY
    env["RUBY_YJIT_ENABLE"] = "1"
  end

  if !pre_steps.empty?
    env["PRE_STEPS"] = pre_steps.join(" && ")
  end
  command = "rake #{rake_task}"

  timeout = 30

  group =
    if rake_task.include?("isolated")
      "isolated"
    else
      ruby || ONE_RUBY
    end

  # TODO MYSQL_IMAGE, POSTGRES_IMAGE
  if RAILS_VERSION < Gem::Version.new("5.x")
    env["MYSQL_IMAGE"] = "mysql:5.6"
  elsif RAILS_VERSION < Gem::Version.new("6.x")
    env["MYSQL_IMAGE"] = "mysql:5.7"
  end

  if RAILS_VERSION < Gem::Version.new("5.2.x")
    env["POSTGRES_IMAGE"] = "postgres:9.6-alpine"
  end

  hash = {
    "label" => label,
    "depends_on" => "docker-image-#{ruby_image(ruby || ONE_RUBY).gsub(/\W/, "-")}",
    "command" => command,
    "group" => group,
    "plugins" => [
      {
        ARTIFACTS_PLUGIN => {
          "download" => [".buildkite/*", ".buildkite/**/*"],
        },
      },
      {
        DOCKER_COMPOSE_PLUGIN => {
          "env" => [
            "PRE_STEPS",
            "RACK"
          ],
          "run" => service,
          "pull" => service,
          "config" => ".buildkite/docker-compose.yml",
          "shell" => ["runner", subdirectory],
        },
      },
    ],
    "env" => env,
    "timeout_in_minutes" => timeout,
    "soft_fail" => SOFT_FAIL.include?(ruby),
    "agents" => { "queue" => RUN_QUEUE },
    "artifact_paths" => ["test-reports/*/*.xml"],
    "retry" => { "automatic" => { "exit_status" => -1, "limit" => 2 } },
  }

  yield hash if block_given?

  STEPS << hash
end

def steps_for(subdirectory, rake_task, service: "default", pre_steps: [], &block)
  RUBIES.each do |ruby|
    step_for(subdirectory, rake_task, ruby: ruby, service: service, pre_steps: pre_steps, &block)
  end
end

# Ugly hacks to just get the build passing for now
STEPS.find { |s| s["label"] == "activestorage (2.2)" }&.tap do |s|
  s["soft_fail"] = true
end
if RAILS_VERSION < Gem::Version.new("7.x") && RAILS_VERSION >= Gem::Version.new("6.1")
  STEPS.delete_if { |s| s["label"] == "guides (2.7)" || s["label"] == "guides (3.0)" }
end
STEPS.delete_if { |s| s["label"] =~ /^guides/ } if RAILS_VERSION < Gem::Version.new("7.0")

###

STEPS.sort_by! do |step|
  [
    -step["timeout_in_minutes"],
    step["group"] == "isolated" ? 2 : 1,
    step["command"].include?("test:") ? 2 : 1,
    step["label"],
  ]
end

groups = STEPS.group_by { |s| s.delete("group") }.map do |group, steps|
  { "group" => group, "steps" => steps }
end

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
    group do
      label ruby

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

        compose subdirectory: dir, rake_task: task, ruby: ruby, service: service

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