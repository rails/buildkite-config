# frozen_string_literal: true

require "buildkite-builder"

module Buildkite::Config
  class BuildContext < Buildkite::Builder::Extension
    attr_accessor :ruby
    attr_reader :rubies

    dsl do
      def build_context
        context.extensions.find(BuildContext)
      end
    end

    def rails_root
      if ci? && %w[rails-ci rails-sandbox zzak/rails].include?(pipeline_name)
        Pathname.pwd
      else
        Pathname.pwd.join("tmp/rails")
      end
    end

    def rails_version
      Gem::Version.new(rails_version_file)
    end

    def default_ruby
      rubies.select { |r| !r.soft_fail? }.first
    end

    def setup_rubies(ruby_minors)
      @rubies = ruby_minors.sort.map { |m| Gem::Version.new(m) }.select { |v| v >= min_ruby }.map do |v|
        rc = RubyConfig.new(version: v, prefix: "ruby:")

        if max_ruby && v > max_ruby && !(max_ruby.approximate_recommendation === v)
          rc.soft_fail = true
        end

        rc
      end.tap do |rubies|
        rubies.reverse!

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

    # IMAGE_BASE = "buildkite-config-base"
    def image_base
      ENV["DOCKER_IMAGE"] || remote_image_base
    end

    def build_id
      ENV["BUILDKITE_BUILD_ID"] || ENV["BUILD_ID"] || "build_id"
    end

    def rebuild_id
      ([ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]] - [""]).first
    end

    def base_branch
      ([ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"], ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
    end

    def local_branch
      ([ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
    end

    def mainline
      local_branch == "main" || local_branch =~ /\A[0-9-]+(?:-stable)?\z/
    end

    def ci?
      ENV.has_key?("BUILDKITE") || ENV.has_key?("CI")
    end

    def pipeline_name
      ENV["BUILDKITE_PIPELINE_NAME"] || "rails-ci"
    end

    def pull_request
      ([ENV["BUILDKITE_PULL_REQUEST"]] - ["false"]).first
    end

    def standard_queues
      [nil, "default", "builder"]
    end

    # If the pipeline is running in a non-standard queue, default to
    # running everything in that queue.
    def queue
      unless standard_queues.include?(ENV["BUILDKITE_AGENT_META_DATA_QUEUE"])
        ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
      end
    end

    def build_queue
      ENV["BUILD_QUEUE"] || queue || "builder"
    end

    # RUN_QUEUE = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
    def run_queue
      ENV["RUN_QUEUE"] || queue || "default"
    end

    def artifact_paths
      ["test-reports/*/*.xml"]
    end

    def automatic_retry_on
      { exit_status: -1, limit: 2 }
    end

    def timeout_in_minutes
      30
    end

    private
      def rails_version_file
        rails_root.join("RAILS_VERSION").read
      end

      def rails_gemspec
        rails_root.join("rails.gemspec").read
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

      def remote_image_base
        "973266071021.dkr.ecr.us-east-1.amazonaws.com/#{"#{build_queue}-" unless standard_queues.include?(build_queue)}builds"
      end
  end
end
