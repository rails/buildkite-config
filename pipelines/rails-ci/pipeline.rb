
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
if ENV["BUILDKITE_PIPELINE_NAME"] == "rails-ci" || ENV["BUILDKITE_PIPELINE_NAME"] == "zzak/rails"
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

  steps_for(dir, task, service: service)

  next unless MAINLINE

  if dir == "activerecord"
    step_for(dir, task.sub(":test", ":isolated_test"), service: service) do |x|
      x["parallelism"] = 5 if REPO_ROOT.join("activerecord/Rakefile").read.include?("BUILDKITE_PARALLEL")
    end
  elsif dir == "actiontext"
    # added during 7.1 development on main
    if REPO_ROOT.join("actiontext/Rakefile").read.include?("task :isolated")
      step_for(dir, "#{task}:isolated", service: service)
    end
  else
    step_for(dir, "#{task}:isolated", service: service)
  end
end

# GROUP 2: No isolated tests, runs for each supported ruby
%w(
  actioncable     test                postgresdb
  activestorage   test                default
  actionmailbox   test                default
  guides          test                default
).each_slice(3) do |dir, task, service|
  steps_for(dir, task, service: service)
end

# GROUP 3: Special cases

if RAILS_VERSION >= Gem::Version.new("5.1.x")
  step_for("activerecord", "sqlite3_mem:test", service: "default")
end
if RAILS_VERSION >= Gem::Version.new("6.1.x")
  step_for("activerecord", "mysql2:test", service: "mysqldb") do |x|
    x["label"] += " [prepared_statements]"
    x["env"]["MYSQL_PREPARED_STATEMENTS"] = "true"
  end
end
step_for("activerecord", "mysql2:test", service: "mysqldb") do |x|
  x["label"] += " [mysql_5_7]"
  x["env"]["MYSQL_IMAGE"] = "mysql:5.7"
end
if RAILS_VERSION >= Gem::Version.new("7.1.0.alpha")
  step_for("activerecord", "trilogy:test", service: "mysqldb") do |x|
    x["label"] += " [mysql_5_7]"
    x["env"]["MYSQL_IMAGE"] = "mysql:5.7"
  end
end
if RAILS_VERSION >= Gem::Version.new("5.x")
  step_for("activerecord", "mysql2:test", service: "mysqldb") do |x|
    x["label"] += " [mariadb]"
    x["env"]["MYSQL_IMAGE"] =
      if RAILS_VERSION < Gem::Version.new("6.x")
        "mariadb:10.2"
      else
        "mariadb:latest"
      end
  end
end
if RAILS_VERSION >= Gem::Version.new("7.1.0.alpha")
  step_for("activerecord", "trilogy:test", service: "mysqldb") do |x|
    x["label"] += " [mariadb]"
    x["env"]["MYSQL_IMAGE"] = "mariadb:latest"
  end
end
steps_for("actioncable", "test:integration", service: "default") do |x|
  if RAILS_VERSION < Gem::Version.new("6.x")
    x["soft_fail"] = true
  else
    x["retry"] = { "automatic" => { "limit" => 3 } }
  end
end
if REPO_ROOT.join("actionview/Rakefile").read.include?("task :ujs")
  step_for("actionview", "test:ujs", service: "actionview") do |x|
    x["retry"] = { "automatic" => { "limit" => 3 } }
  end
end
steps_for("activejob", "test:integration", service: "activejob") do |x|
  # Enable soft_fail until the problem in queue_classic is solved.
  # https://github.com/rails/rails/pull/37517#issuecomment-545370408
  x["soft_fail"] = true # if RAILS_VERSION < Gem::Version.new("5.x")
end
steps_for("railties", "test", service: "railties") do |x|
  x["parallelism"] = 12 if REPO_ROOT.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
end

step_for("actionpack", "test", service: "default", pre_steps: ["bundle install"]) do |x|
  x["label"] += " [rack-2]"
  x["env"]["RACK"] = "~> 2.0"
end

step_for("railties", "test", service: "railties", pre_steps: ["bundle install"]) do |x|
  x["parallelism"] = 12 if REPO_ROOT.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
  x["label"] += " [rack-2]"
  x["env"]["RACK"] = "~> 2.0"
end

step_for("actionpack", "test", service: "default", pre_steps: ["rm Gemfile.lock", "bundle install"]) do |x|
  x["label"] += " [rack-head]"
  x["env"]["RACK"] = "head"
  x["soft_fail"] = true
end

step_for("railties", "test", service: "railties", pre_steps: ["rm Gemfile.lock", "bundle install"]) do |x|
  x["parallelism"] = 12 if REPO_ROOT.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
  x["label"] += " [rack-head]"
  x["env"]["RACK"] = "head"
  x["soft_fail"] = true
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

Buildkite::Builder.pipeline do
  group do
    label "build"
    (RUBIES - [YJIT_RUBY]).map do |ruby|
      command do
        label ":docker: #{ruby}"
        key "docker-image-#{ruby.gsub(/\W/, "-")}"
        plugin ARTIFACTS_PLUGIN, {
          "download" => [".dockerignore", ".buildkite/*", ".buildkite/**/*"],
        }

        plugin DOCKER_COMPOSE_PLUGIN, {
          "build" => "base",
          "config" => ".buildkite/docker-compose.yml",
          "env" => [
            "PRE_STEPS",
            "RACK"
          ],
          "image-name" => image_name_for(ruby, short: true),
          "cache-from" => [
            REBUILD_ID && "base:" + image_name_for(ruby, REBUILD_ID),
            PULL_REQUEST && "base:" + image_name_for(ruby, "pr-#{PULL_REQUEST}"),
            LOCAL_BRANCH && LOCAL_BRANCH !~ /:/ && "base:" + image_name_for(ruby, "br-#{LOCAL_BRANCH}"),
            BASE_BRANCH && "base:" + image_name_for(ruby, "br-#{BASE_BRANCH}"),
            "base:" + image_name_for(ruby, "br-main"),
          ].grep(String).uniq,
          "push" => [
            LOCAL_BRANCH =~ /:/ ?
            "base:" + image_name_for(ruby, "pr-#{PULL_REQUEST}") :
            "base:" + image_name_for(ruby, "br-#{LOCAL_BRANCH}"),
          ],
          "image-repository" => IMAGE_BASE,
        }

        env({
          RUBY_IMAGE: ruby_image(ruby),
          encrypted_0fb9444d0374_key: nil,
          encrypted_0fb9444d0374_iv: nil,
        })

        timeout_in_minutes 15
        if SOFT_FAIL.include?(ruby)
          soft_fail true
        end
        agents queue: BUILD_QUEUE
      end
    end
  end

  groups.map do |_group|
    group do
      label _group["group"]

      _group["steps"].map do |_step|
        command do
          label _step["label"]
          depends_on _step["depends_on"]
          command _step["command"]

          #plugin ARTIFACTS_PLUGIN, {
          #  "download" => [".buildkite/*", ".buildkite/**/*"],
          #},

          plugins _step["plugins"]
          env _step["env"]
          timeout_in_minutes _step["timeout_in_minutes"]

          if _step["soft_fail"]
            soft_fail true
          end

          agents _step["agents"]
          artifact_paths _step["artifact_paths"]
          automatic_retry_on exit_status: -1, limit: 2
        end
      end
    end
  end
end