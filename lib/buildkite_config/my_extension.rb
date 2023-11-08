require "buildkite-builder"

module Buildkite::Config
  class MyExtension < Buildkite::Builder::Extension
    class << self
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
    end

    def prepare
      #context.data.args = options
    end

    def build
      #pipeline do
      #  group do
      #    label to_label
      #  end
      #end
    end

    dsl do
      def component(**args)
        _label = to_label(**args)
        _ruby_image = ruby_image(args[:ruby] || Buildkite::Config::MyExtension.one_ruby).gsub(/\W/, "-")
        _service = args[:service] || "default"
        _pre_steps = args[:pre_steps] || []

        ## Setup ENV
        _env = {
          "IMAGE_NAME" => image_name_for(args[:ruby] || Buildkite::Config::MyExtension.one_ruby)
        }

        if args[:ruby] == Buildkite::Config::MyExtension.yjit_ruby
          _env["RUBY_YJIT_ENABLE"] = "1"
        end

        if !(_pre_steps).empty?
          _env["PRE_STEPS"] = _pre_steps.join(" && ")
        end

        command do
          label _label
          depends_on "docker-image-#{_ruby_image}"
          command "rake #{args[:rake_task]}"

          plugin Buildkite::Config::MyExtension.artifacts_plugin, {
            download: %w[.buildkite/* .buildkite/*/*]
          }

          plugin Buildkite::Config::MyExtension.docker_compose_plugin,{
            "env" => [
              "PRE_STEPS",
              "RACK"
            ],
            "run" => _service,
            "pull" => _service,
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", args[:subdirectory]],
          }

          env _env
          agents queue: Buildkite::Config::MyExtension.run_queue
          artifact_paths Buildkite::Config::MyExtension.artifact_paths
          automatic_retry_on(**Buildkite::Config::MyExtension.automatic_retry_on)
          timeout_in_minutes Buildkite::Config::MyExtension.timeout_in_minutes
          soft_fail args[:soft_fail] || false
        end
      end


      ## Helpers

      def image_name_for(ruby, suffix = Buildkite::Config::MyExtension.build_id, short: false)
        ruby = ruby_image(ruby)

        tag = "#{mangle_name(ruby)}-#{suffix}"

        if short
          tag
        else
          "#{Buildkite::Config::MyExtension.image_base}:#{tag}"
        end
      end

      def mangle_name(name)
        name.tr("^A-Za-z0-9", "-")
      end

      def ruby_image(ruby)
        if ruby == Buildkite::Config::MyExtension.yjit_ruby
          ruby.sub("yjit:", "")
        else
          ruby
        end
      end

      # A shortened version of the name for the Buildkite label.
      def short_ruby(ruby)
        if ruby == Buildkite::Config::MyExtension.master_ruby
          "master"
        elsif ruby == Buildkite::Config::MyExtension.yjit_ruby
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
end
