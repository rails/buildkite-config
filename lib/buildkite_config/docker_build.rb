require "buildkite-builder"

module Buildkite::Config
  class DockerBuild < Buildkite::Builder::Extension
    dsl do
      def builder(**args, &block)
        build_context = context.extensions.find(BuildContext)
        build_context.ruby = RubyConfig.new(version: args[:ruby], image_base: build_context.image_base)

        command do
          label ":docker: #{args[:ruby]}"
          key "docker-image-#{args[:ruby].gsub(/\W/, "-")}"
          plugin build_context.artifacts_plugin, {
            download: %w[.dockerignore .buildkite/* .buildkite/**/*]
          }

          plugin build_context.docker_compose_plugin,{
            build: "base",
            config: ".buildkite/docker-compose.yml",
            env: %w[PRE_STEPS RACK],
            "image-name" => build_context.ruby.image_name_for(build_context.build_id, short: true),
            "cache-from" => [
              build_context.rebuild_id && "base:" + build_context.ruby.image_name_for(build_context.rebuild_id),
              build_context.pull_request && "base:" + build_context.ruby.image_name_for("pr-#{build_context.pull_request}"),
              build_context.local_branch && build_context.local_branch !~ /:/ && "base:" + build_context.ruby.image_name_for("br-#{build_context.local_branch}"),
              build_context.base_branch && "base:" + build_context.ruby.image_name_for("br-#{build_context.base_branch}"),
              "base:" + build_context.ruby.image_name_for("br-main"),
            ].grep(String).uniq,
            push: [
              build_context.local_branch =~ /:/ ?
                "base:" + build_context.ruby.image_name_for("pr-#{build_context.pull_request}") :
                "base:" + build_context.ruby.image_name_for("br-#{build_context.local_branch}"),
            ],
            "image-repository" => build_context.image_base,
          }

          env({
            RUBY_IMAGE: build_context.ruby.ruby_image,
            encrypted_0fb9444d0374_key: nil,
            encrypted_0fb9444d0374_iv: nil
          })

          timeout_in_minutes 15

          if build_context.ruby.soft_fail?
            soft_fail true
          end
          agents queue: build_context.build_queue

          instance_exec(@attributes, &block) if block_given?
        end
      end
    end
  end
end
