require "buildkite-builder"

module Buildkite::Config
  class Context
    attr_reader :options
    def initialize(**options)
      @options = options
    end

    # ONE_RUBY = "3.2"#RUBIES.last || SOFT_FAIL.last
    def one_ruby
      @one_ruby ||= "3.2"
    end

    # MASTER_RUBY = "rubylang/ruby:master-nightly-jammy"
    def master_ruby
      @master_ruby ||= "rubylang/ruby:master-nightly-jammy"
    end

    # Adds yjit: onto the master ruby image string so we
    # know when to turn on YJIT via the environment variable.
    # Same as master ruby, we want this to soft fail.
    # YJIT_RUBY = "yjit:#{MASTER_RUBY}"
    def yjit_ruby
      @yjit_ruby ||= "yjit:#{master_ruby}"
    end

    def soft_fail
      @soft_fail ||= []
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
      @local ||= ENV["BUILD_ID"]
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
      @artifact_paths ||= ["test-results/*/*.xml"]
    end

    def automatic_retry_on
      @automatic_retry_on ||= { exit_status: -1, limit: 2 }
    end

    def timeout_in_minutes
      @timeout_in_minutes ||= 30
    end

    ## Helpers

    def image_name_for(ruby, suffix = build_id, short: false)
      ruby = ruby_image(ruby)

      tag = "#{mangle_name(ruby)}-#{suffix}"

      if short
        tag
      else
        "#{image_base}:#{tag}"
      end
    end

    def ruby_image(ruby)
      if ruby == yjit_ruby
        ruby.sub("yjit:", "")
      else
        ruby
      end
    end

    def to_label(ruby, dir, task = "")
      str = +"#{dir} #{task.sub(/[:_]test|test:/, "")}"
      str.sub!(/ test/, "")
      return str unless ruby

      str << " (#{short_ruby(ruby)})"
    end

    private
      def mangle_name(name)
        name.tr("^A-Za-z0-9", "-")
      end

      # A shortened version of the name for the Buildkite label.
      def short_ruby(ruby)
        if ruby == master_ruby
          "master"
        elsif ruby == yjit_ruby
          "yjit"
        else
          ruby.sub(/^ruby:|:latest$/, "")
        end
      end
  end
end
