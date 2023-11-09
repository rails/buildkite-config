require "buildkite-builder"

module Buildkite::Config
  class MyExtension < Buildkite::Builder::Extension
    attr_accessor :context

    def prepare
      @context = Context.new(**options)
    end

    dsl do
      def my_context
        context.extensions.find(MyExtension).context
      end

      def component(**args, &block)
        _my_context = my_context

        _ruby_image = _my_context.ruby_image(args[:ruby] || _my_context.one_ruby).gsub(/\W/, "-")
        _service = args[:service] || "default"
        _pre_steps = args[:pre_steps] || []

        ## Setup ENV
        _env = {
          "IMAGE_NAME" => _my_context.image_name_for(args[:ruby] || _my_context.one_ruby)
        }

        if args[:ruby] == _my_context.yjit_ruby
          _env["RUBY_YJIT_ENABLE"] = "1"
        end

        if !(_pre_steps).empty?
          _env["PRE_STEPS"] = _pre_steps.join(" && ")
        end

        #_my_context.my_var = "override"

        command do
          label _my_context.to_label(**args)
          depends_on "docker-image-#{_ruby_image}"
          command "rake #{args[:rake_task]}"

          plugin _my_context.artifacts_plugin, {
            download: %w[.buildkite/* .buildkite/*/*]
          }

          plugin _my_context.docker_compose_plugin,{
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
          #env["my_var"] = _my_context.my_var
          agents queue: _my_context.run_queue
          artifact_paths _my_context.artifact_paths
          automatic_retry_on(**_my_context.automatic_retry_on)
          timeout_in_minutes _my_context.timeout_in_minutes
          soft_fail args[:soft_fail] || false

          instance_exec(@attributes, &block) if block_given?
        end
      end
    end
  end
end
