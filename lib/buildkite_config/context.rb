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

    # DOCKER_COMPOSE_PLUGIN = "docker-compose#v3.7.0"
    def docker_compose_plugin
      @docker_compose_plugin ||= "docker-compose#v3.7.0"
    end

    # ARTIFACTS_PLUGIN = "artifacts#v1.2.0"
    def artifacts_plugin
      @artifacts_plugin ||= "artifacts#v1.2.0"
    end

    # IMAGE_BASE = "buildkite-config-base"
    def image_base
      @image_base ||= "buildkite-config-base"
    end

    # BUILD_ID = "local"
    def build_id
      @local ||= "local"
    end

    # RUN_QUEUE = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
    def run_queue
      @run_queue ||= ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
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

    def mangle_name(name)
      name.tr("^A-Za-z0-9", "-")
    end

    def ruby_image(ruby)
      if ruby == yjit_ruby
        ruby.sub("yjit:", "")
      else
        ruby
      end
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

    def to_label(**args)
      str = +"#{args[:subdirectory]} #{(args[:rake_task] || "").sub(/[:_]test|test:/, "")}"
      str.sub!(/ test/, "")
      return str unless args[:ruby]

      str << " (#{short_ruby(args[:ruby])})"
    end
  end
end
