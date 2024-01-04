module Buildkite::Config
  class Generate
    STANDARD_QUEUES = [nil, "default", "builder"]
    ARTIFACTS_PLUGIN = "artifacts#v1.2.0"
    DOCKER_COMPOSE_PLUGIN = "docker-compose#v3.7.0"

    attr_reader :build_queue
    attr_reader :run_queue
    attr_reader :image_base
    attr_reader :base_branch
    attr_reader :local_branch
    attr_reader :pull_request
    attr_reader :build_id
    attr_reader :rebuild_id
    attr_reader :root
    attr_reader :rails_version
    attr_reader :steps

    attr_accessor :default_ruby
    attr_accessor :soft_fail
    attr_accessor :rubies

    def initialize(root)
      setup_queue

      @steps = []

      @root = Pathname.new(root)

      @build_queue = ENV["BUILD_QUEUE"] || ENV["QUEUE"] || "builder"
      @run_queue = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
      @image_base = ENV["DOCKER_IMAGE"] || "973266071021.dkr.ecr.us-east-1.amazonaws.com/#{"#{build_queue}-" unless STANDARD_QUEUES.include?(build_queue)}builds"
      @base_branch = ([ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"], ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
      @local_branch = ([ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
      @pull_request = ([ENV["BUILDKITE_PULL_REQUEST"]] - ["false"]).first
      @build_id = ENV["BUILDKITE_BUILD_ID"]
      @rebuild_id = ([ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]] - [""]).first
      @rails_version = Gem::Version.new(File.read(@root.join("RAILS_VERSION")))
    end

    def mainline?
      local_branch == "main" || local_branch =~ /\A[0-9-]+(?:-stable)?\z/
    end

    def bundler
      case rails_version
      when Gem::Requirement.new("< 5.0")
        "< 2"
      when Gem::Requirement.new("< 6.1")
        "< 2.2.10"
      end
    end

    def rubygems
      case rails_version
      when Gem::Requirement.new("< 5.0")
        "2.6.13"
      when Gem::Requirement.new("< 6.1")
        "3.2.9"
      end
    end

    def image_name_for(ruby, suffix = nil, short: false)
      ruby = ruby_image(ruby)

      tag = "#{mangle_name(ruby)}-#{suffix || build_id}"

      if short
        tag
      else
        "#{image_base}:#{tag}"
      end
    end

    def ruby_image(ruby)
      # YJIT uses the same image as ruby-trunk because it's turned on
      # via an ENV var. This needs to remove the `yjit:` added onto the
      # front because otherwise it's not a valid image.
      if yjit?(ruby)
        ruby.sub("yjit:", "")
      else
        ruby
      end
    end

    def add_steps_for(subdirectory, rake_task, service: "default", pre_steps: [], &block)
      rubies.each do |ruby|
        add_step_for(subdirectory, rake_task, ruby: ruby, service: service, pre_steps: pre_steps, &block)
      end
    end

    def add_step_for(subdirectory, rake_task, ruby: nil, service: "default", pre_steps: [])
      return unless root.join(subdirectory).exist?

      label = +"#{subdirectory} #{rake_task.sub(/[:_]test|test:/, "")}"
      label.sub!(/ test/, "")
      if ruby
        label << " (#{short_ruby(ruby)})"
      end

      if rake_task.start_with?("mysql2:") || (rails_version >= Gem::Version.new("7.1.0.alpha") && rake_task.start_with?("trilogy:"))
        rake_task = "db:mysql:rebuild #{rake_task}"
      elsif rake_task.start_with?("postgresql:")
        rake_task = "db:postgresql:rebuild #{rake_task}"
      end

      env = {
        "IMAGE_NAME" => image_name_for(ruby || default_ruby),
      }

      # If we have YJIT_RUBY set the environment variable
      # to turn it on.
      if yjit?(ruby)
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
          ruby || default_ruby
        end

      if rails_version < Gem::Version.new("5.x")
        env["MYSQL_IMAGE"] = "mysql:5.6"
      elsif rails_version < Gem::Version.new("6.x")
        env["MYSQL_IMAGE"] = "mysql:5.7"
      end

      if rails_version < Gem::Version.new("5.2.x")
        env["POSTGRES_IMAGE"] = "postgres:9.6-alpine"
      end

      hash = {
        "label" => label,
        "depends_on" => "docker-image-#{ruby_image(ruby || default_ruby).gsub(/\W/, "-")}",
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
        "soft_fail" => soft_fail.include?(ruby),
        "agents" => { "queue" => run_queue },
        "artifact_paths" => ["test-reports/*/*.xml"],
        "retry" => { "automatic" => { "exit_status" => -1, "limit" => 2 } },
      }

      yield hash if block_given?

      self.steps << hash
    end

    private

    def setup_queue
      # If the pipeline is running in a non-standard queue, default to
      # running everything in that queue.
      unless STANDARD_QUEUES.include?(ENV["BUILDKITE_AGENT_META_DATA_QUEUE"])
        ENV["QUEUE"] ||= ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
      end
    end

    def mangle_name(name)
      name.tr("^A-Za-z0-9", "-")
    end

    # A shortened version of the name for the Buildkite label.
    def short_ruby(ruby)
      if ruby.match?(%r{^rubylang/ruby:master})
        "master"
      elsif yjit?(ruby)
        "yjit"
      else
        ruby.sub(/^ruby:|:latest$/, "")
      end
    end

    def yjit?(ruby)
      return false unless ruby

      ruby.start_with?("yjit:")
    end
  end
end
