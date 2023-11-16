require "buildkite-builder"

module Buildkite::Config
  class BuildContext < Buildkite::Builder::Extension
    attr_accessor :ruby

    def prepare
      @ruby = RubyConfig.new(image_base: image_base)
    end

    dsl do
      def build_context
        context.extensions.find(BuildContext)
      end
    end

    def rails_root
      if ci? && %w[rails-ci config-sandbox rails-sandbox zzak/rails].include?(pipeline_name)
        Pathname.new(Dir.pwd)
      else
        Pathname.new(Dir.pwd) + "tmp/rails"
      end
    end

    def rails_gemspec
      rails_root.join("rails.gemspec").read
    end

    def rails_version_file
      rails_root.join("RAILS_VERSION").read
    end

    def rails_version
      Gem::Version.new(rails_version_file)
    end

    def min_ruby
      # Sets $1 below for MIN_RUBY
      # e.g.:
      #   >> rails_root.join("rails.gemspec").read =~ /required_ruby_version[^0-9]+([0-9]+\.[0-9]+)/
      #   #=> 486
      #   >> Gem::Version.new($1)
      #   #=> Gem::Version.new("2.7")
      rails_gemspec =~ /required_ruby_version[^0-9]+([0-9]+\.[0-9]+)/
      Gem::Version.new($1 || "2.0")
    end

    def ruby_minors
      %w(2.4 2.5 2.6 2.7 3.0 3.1 3.2).map { |v| Gem::Version.new(v) }
    end

    def rubies
      @rubies ||= ruby_minors.select { |v| v >= min_ruby }.map do |v|
        rc = RubyConfig.new(version: v)

        if max_ruby && v > max_ruby && !(max_ruby.approximate_recommendation === v)
          rc.soft_fail = true
        end

        rc
      end.tap do |rubies|
        rubies.reverse!

        rubies << RubyConfig.new(version: RubyConfig.yjit_ruby, soft_fail: true, build: false)
        rubies << RubyConfig.new(version: RubyConfig.master_ruby, soft_fail: true)

        rubies.sort_by { |r| [r.version.to_s, r.soft_fail] }
      end
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

    def max_ruby
      case rails_version
      when Gem::Requirement.new("< 5.1")
        Gem::Version.new("2.4")
      when Gem::Requirement.new("< 5.2")
        Gem::Version.new("2.5")
      when Gem::Requirement.new("< 6.0")
        Gem::Version.new("2.6")
      when Gem::Requirement.new("< 6.1")
        Gem::Version.new("2.7")
      end
    end

    # DOCKER_COMPOSE_PLUGIN = "docker-compose#v3.7.0"
    def docker_compose_plugin
      @docker_compose_plugin ||= "docker-compose#v3.7.0"
    end

    # ARTIFACTS_PLUGIN = "artifacts#v1.2.0"
    def artifacts_plugin
      @artifacts_plugin ||= "artifacts#v1.2.0"
    end

    def remote_image_base
      @remote_image_base ||= "973266071021.dkr.ecr.us-east-1.amazonaws.com/#{"#{build_queue}-" unless standard_queues.include?(build_queue)}builds"
    end

    # IMAGE_BASE = "buildkite-config-base"
    def image_base
      @image_base ||= ENV["DOCKER_IMAGE"] || remote_image_base
    end

    def build_id
      @local ||= ENV["BUILDKITE_BUILD_ID"] || ENV["BUILD_ID"]
    end

    def rebuild_id
      @rebuild_id ||= ([ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]] - [""]).first
    end

    def base_branch
      @base_branch ||= ([ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"], ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
    end

    def local_branch
      @local_branch ||= ([ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
    end

    def mainline
      local_branch == "main" || local_branch =~ /\A[0-9-]+(?:-stable)?\z/
    end

    def ci?
      @ci ||= ENV.has_key?("BUILDKITE") || ENV.has_key?("CI")
    end

    def pipeline_name
      @pipeline_name ||= ENV["BUILDKITE_PIPELINE_NAME"] || "rails-ci"
    end

    def pull_request
      @pull_request ||= ([ENV["BUILDKITE_PULL_REQUEST"]] - ["false"]).first
    end

    def standard_queues
      @standard_queues ||= [nil, "default", "builder"]
    end

    # If the pipeline is running in a non-standard queue, default to
    # running everything in that queue.
    def queue
      unless standard_queues.include?(ENV["BUILDKITE_AGENT_META_DATA_QUEUE"])
        @queue ||= ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
      end
    end

    def build_queue
      @build_queue ||= ENV["BUILD_QUEUE"] || queue || "builder"
    end

    # RUN_QUEUE = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
    def run_queue
      @run_queue ||= ENV["RUN_QUEUE"] || queue || "default"
    end

    def artifact_paths
      @artifact_paths ||= ["test-reports/*/*.xml"]
    end

    def automatic_retry_on
      @automatic_retry_on ||= { exit_status: -1, limit: 2 }
    end

    def timeout_in_minutes
      @timeout_in_minutes ||= 30
    end
  end
end
