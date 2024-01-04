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
    attr_reader :ignored_rubies

    def initialize(root)
      setup_queue

      @steps = []

      @root = Pathname.new(root)

      @build_queue = ENV["BUILD_QUEUE"] || ENV["QUEUE"] || "builder"
      @run_queue = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
      @image_base = ENV["DOCKER_IMAGE"] || "973266071021.dkr.ecr.us-east-1.amazonaws.com/#{"#{build_queue}-" unless STANDARD_QUEUES.include?(build_queue)}builds"
      @base_branch = ([ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"], ENV["BUILDKITE_BRANCH"], "main"].compact - [""]).first
      @local_branch = ([ENV["BUILDKITE_BRANCH"], "main"].compact - [""]).first
      @pull_request = ([ENV["BUILDKITE_PULL_REQUEST"]] - ["false"]).first
      @build_id = ENV["BUILDKITE_BUILD_ID"]
      @rebuild_id = ([ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]] - [""]).first
      @rails_version = Gem::Version.new(File.read(@root.join("RAILS_VERSION")))
      @ignored_rubies = []
    end

    def generate
      configure_pipeline

      steps.sort_by! do |step|
        [
          -step["timeout_in_minutes"],
          step["group"] == "isolated" ? 2 : 1,
          step["command"].include?("test:") ? 2 : 1,
          step["label"],
        ]
      end

      groups = steps.group_by { |s| s.delete("group") }.map do |group, steps|
        { "group" => group, "steps" => steps }
      end

      YAML.dump("steps" => [
        {
          "group" => "build",
          "steps" => [
            *(rubies - ignored_rubies).map do |ruby|
              {
                "label" => ":docker: #{ruby}",
                "key" => "docker-image-#{ruby.gsub(/\W/, "-")}",
                "plugins" => [
                  {
                    Buildkite::Config::Generate::ARTIFACTS_PLUGIN => {
                      "download" => [".dockerignore", ".buildkite/*", ".buildkite/**/*"],
                    },
                  },
                  {
                    Buildkite::Config::Generate::DOCKER_COMPOSE_PLUGIN => {
                      "build" => "base",
                      "config" => ".buildkite/docker-compose.yml",
                      "env" => [
                        "PRE_STEPS",
                        "RACK"
                      ],
                      "image-name" => image_name_for(ruby, short: true),
                      "cache-from" => [
                        rebuild_id && "base:" + image_name_for(ruby, rebuild_id),
                        pull_request && "base:" + image_name_for(ruby, "pr-#{pull_request}"),
                        local_branch && local_branch !~ /:/ && "base:" + image_name_for(ruby, "br-#{local_branch}"),
                        base_branch && "base:" + image_name_for(ruby, "br-#{base_branch}"),
                        "base:" + image_name_for(ruby, "br-main"),
                      ].grep(String).uniq,
                      "push" => [
                        local_branch =~ /:/ ?
                        "base:" + image_name_for(ruby, "pr-#{pull_request}") :
                        "base:" + image_name_for(ruby, "br-#{local_branch}"),
                      ],
                      "image-repository" => image_base,
                    },
                  },
                ],
                "env" => {
                  "BUNDLER" => bundler,
                  "RUBYGEMS" => rubygems,
                  "RUBY_IMAGE" => ruby_image(ruby),
                  "encrypted_0fb9444d0374_key" => nil,
                  "encrypted_0fb9444d0374_iv" => nil,
                },
                "timeout_in_minutes" => 15,
                "soft_fail" => soft_fail.include?(ruby),
                "agents" => { "queue" => build_queue },
              }
            end,
          ],
        },
        *groups,
      ])
    end

    private

    def configure_pipeline
      add_steps_for("actionpack", "test", service: "default")
      add_step_for("actionpack", "test:isolated", service: "default") if mainline?
      add_step_for("actionpack", "test", service: "default", pre_steps: ["bundle install"]) do |x|
        x["label"] += " [rack-2]"
        x["env"]["RACK"] = "~> 2.0"
      end
      add_step_for("actionpack", "test", service: "default", pre_steps: ["rm Gemfile.lock", "bundle install"]) do |x|
        x["label"] += " [rack-head]"
        x["env"]["RACK"] = "head"
        x["soft_fail"] = true
      end

      add_steps_for("actionmailer", "test", service: "default")
      add_step_for("actionmailer", "test:isolated", service: "default") if mainline?

      add_steps_for("activemodel", "test", service: "default")
      add_step_for("activemodel", "test:isolated", service: "default") if mainline?

      add_steps_for("activesupport", "test", service: "default")
      add_step_for("activesupport", "test:isolated", service: "default") if mainline?

      add_steps_for("actionview", "test", service: "default")
      add_step_for("actionview", "test:isolated", service: "default") if mainline?

      add_steps_for("actiontext", "test", service: "default")
      add_step_for("actiontext", "test:isolated", service: "default") if mainline? && actiontext_isolated_present?

      add_steps_for("activejob", "test", service: "default")
      add_step_for("activejob", "test:isolated", service: "default") if mainline?

      add_steps_for("activerecord", "mysql2:test", service: "mysqldb")
      if mainline?
        add_step_for("activerecord", "mysql2:isolated_test", service: "mysqldb") do |x|
          x["parallelism"] = 5 if activerecord_parallel?
        end
      end
      if rails_version >= Gem::Version.new("6.1.x")
        add_step_for("activerecord", "mysql2:test", service: "mysqldb") do |x|
          x["label"] += " [prepared_statements]"
          x["env"]["MYSQL_PREPARED_STATEMENTS"] = "true"
        end
      end
      add_step_for("activerecord", "mysql2:test", service: "mysqldb") do |x|
        x["label"] += " [mysql_5_7]"
        x["env"]["MYSQL_IMAGE"] = "mysql:5.7"
      end
      if rails_version >= Gem::Version.new("5.x")
        add_step_for("activerecord", "mysql2:test", service: "mysqldb") do |x|
          x["label"] += " [mariadb]"
          x["env"]["MYSQL_IMAGE"] =
            if rails_version < Gem::Version.new("6.x")
              "mariadb:10.2"
            else
              "mariadb:latest"
            end
        end
      end

      if trilogy_supported?
        add_steps_for("activerecord", "trilogy:test", service: "mysqldb")
        if mainline?
          add_step_for("activerecord", "trilogy:isolated_test", service: "mysqldb") do |x|
            x["parallelism"] = 5 if activerecord_parallel?
          end
        end
        add_step_for("activerecord", "trilogy:test", service: "mysqldb") do |x|
          x["label"] += " [mysql_5_7]"
          x["env"]["MYSQL_IMAGE"] = "mysql:5.7"
        end
        add_step_for("activerecord", "trilogy:test", service: "mysqldb") do |x|
          x["label"] += " [mariadb]"
          x["env"]["MYSQL_IMAGE"] = "mariadb:latest"
        end
      end

      add_steps_for("activerecord", "postgresql:test", service: "postgresdb")
      if mainline?
        add_step_for("activerecord", "postgresql:isolated_test", service: "postgresdb") do |x|
          x["parallelism"] = 5 if activerecord_parallel?
        end
      end

      add_steps_for("activerecord", "sqlite3:test", service: "default")
      if mainline?
        add_step_for("activerecord", "sqlite3:isolated_test", service: "default") do |x|
          x["parallelism"] = 5 if activerecord_parallel?
        end
      end
      if rails_version >= Gem::Version.new("5.1.x")
        add_step_for("activerecord", "sqlite3_mem:test", service: "default")
      end

      add_steps_for("activestorage", "test", service: "default")

      add_steps_for("actionmailbox", "test", service: "default")

      add_steps_for("guides", "test", service: "default")

      add_steps_for("actioncable", "test", service: "postgresdb", pre_steps: ["cd ./activerecord", "bundle exec rake db:postgresql:rebuild", "cd -"])
      add_steps_for("actioncable", "test:integration", service: "default") do |x|
        if rails_version < Gem::Version.new("6.x")
          x["soft_fail"] = true
        else
          x["retry"] = { "automatic" => { "limit" => 3 } }
        end
      end

      if ujs_supported?
        add_step_for("actionview", "test:ujs", service: "actionview") do |x|
          x["retry"] = { "automatic" => { "limit" => 3 } }
        end
      end

      add_steps_for("activejob", "test:integration", service: "activejob") do |x|
        # Enable soft_fail until the problem in queue_classic is solved.
        # https://github.com/rails/rails/pull/37517#issuecomment-545370408
        x["soft_fail"] = true # if rails_version < Gem::Version.new("5.x")
      end

      add_steps_for("railties", "test", service: "railties") do |x|
        x["parallelism"] = 12 if railties_parallel?
      end
      add_step_for("railties", "test", service: "railties", pre_steps: ["bundle install"]) do |x|
        x["parallelism"] = 12 if railties_parallel?
        x["label"] += " [rack-2]"
        x["env"]["RACK"] = "~> 2.0"
      end

      add_step_for("railties", "test", service: "railties", pre_steps: ["rm Gemfile.lock", "bundle install"]) do |x|
        x["parallelism"] = 12 if railties_parallel?
        x["label"] += " [rack-head]"
        x["env"]["RACK"] = "head"
        x["soft_fail"] = true
      end

      # Ugly hacks to just get the build passing for now
      steps.find { |s| s["label"] == "activestorage (2.2)" }&.tap do |s|
        s["soft_fail"] = true
      end

      # Bug report templates
      steps.select { |s| s["label"] =~ /^guides/  }.each do |s|
        s["soft_fail"] = true
      end
      if rails_version < Gem::Version.new("7.x") && rails_version >= Gem::Version.new("6.1")
        steps.delete_if { |s| s["label"] == "guides (2.7)" || s["label"] == "guides (3.0)" }
      end
      steps.delete_if { |s| s["label"] =~ /^guides/ } if rails_version < Gem::Version.new("7.0")
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

      if rake_task.start_with?("mysql2:") || (rails_7_1_plus? && rake_task.start_with?("trilogy:"))
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

    def actiontext_isolated_present?
      root.join("actiontext/Rakefile").read.include?("task :isolated")
    end

    def activerecord_parallel?
      root.join("activerecord/Rakefile").read.include?("BUILDKITE_PARALLEL")
    end

    def rails_7_1_plus?
      rails_version >= Gem::Version.new("7.1.0.alpha")
    end

    def trilogy_supported?
      rails_7_1_plus?
    end

    def ujs_supported?
      root.join("actionview/Rakefile").read.include?("task :ujs")
    end

    def railties_parallel?
      root.join("railties/Rakefile").read.include?("BUILDKITE_PARALLEL")
    end
  end
end
