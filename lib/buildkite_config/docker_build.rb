require "buildkite-builder"

module Buildkite::Config
  class DockerBuild < Buildkite::Builder::Extension
    attr_accessor :context

    def prepare
      @context = Context.new(**options)
    end

    dsl do
      def my_context
        context.extensions.find(DockerBuild).context
      end

      def builder(**args, &block)
        _my_context = my_context

        _ruby_image = _my_context.ruby_image(args[:ruby] || _my_context.one_ruby).gsub(/\W/, "-")
        _service = args[:service] || "default"
        _pre_steps = args[:pre_steps] || []

        ## Setup ENV
        _env = {
          "RUBY_IMAGE" => _my_context.ruby_image(args[:ruby])
        }

        #_my_context.my_var = "override"

        command do
          label ":docker: #{args[:ruby]}"
          key "docker-image-#{args[:ruby].gsub(/\W/, "-")}"
          plugin _my_context.artifacts_plugin, {
            download: %w[.dockerignore .buildkite/* .buildkite/*/*]
          }

          plugin _my_context.docker_compose_plugin,{
            build: "base",
            config: ".buildkite/docker-compose.yml",
            env: %w[PRE_STEPS RACK],
            "image-name" => _my_context.image_name_for(args[:ruby], short: true),
            "cache-from" => [
              _my_context.rebuild_id && "base:" + _my_context.image_name_for(ruby, _my_context.rebuild_id),
              _my_context.pull_request && "base:" + _my_context.image_name_for(args[:ruby], "pr-#{my_context.pull_request}"),
              _my_context.local_branch && _my_context.local_branch !~ /:/ && "base:" + _my_context.image_name_for(ruby, "br-#{_my_context.local_branch}"),
              _my_context.base_branch && "base:" + _my_context.image_name_for(args[:ruby], "br-#{_my_context.base_branch}"),
              "base:" + _my_context.image_name_for(args[:ruby], "br-main"),
            ].grep(String).uniq,
            push: [
              _my_context.local_branch =~ /:/ ?
                "base:" + _my_context.image_name_for(args[:ruby], "pr-#{_my_context.pull_request}") :
                "base:" + _my_context.image_name_for(args[:ruby], "br-#{_my_context.local_branch}"),
            ],
            "image-repository" => _my_context.image_base,
          }

          env({
            RUBY_IMAGE: _my_context.ruby_image(args[:ruby]),
            encrypted_0fb9444d0374_key: nil,
            encrypted_0fb9444d0374_iv: nil
          })

          timeout_in_minutes 15

          if _my_context.soft_fail.include?(args[:ruby])
            soft_fail true
          end
          agents queue: _my_context.build_queue

          instance_exec(@attributes, &block) if block_given?
        end
      end
    end
  end
end
