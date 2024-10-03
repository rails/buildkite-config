# frozen_string_literal: true

require "buildkite-builder"

module Buildkite::Config
  class DockerBuild < Buildkite::Builder::Extension
    module Step
      def cache_from(build_context)
        sources = []

        if build_context.rebuild_id
          sources << build_context.image_name_for(build_context.rebuild_id)
        end

        if build_context.pull_request
          sources << build_context.image_name_for("pr-#{build_context.pull_request}")
        end

        if build_context.local_branch && build_context.local_branch !~ /:/
          sources << build_context.image_name_for("br-#{build_context.local_branch}")
        end

        if build_context.base_branch
          sources << build_context.image_name_for("br-#{build_context.base_branch}")
        end

        sources << build_context.image_name_for("br-main")

        sources.grep(String).uniq
      end

      def build_push(build_context)
        [
          build_context.local_branch =~ /:/ ?
            build_context.image_name_for("pr-#{build_context.pull_request}") :
            build_context.image_name_for("br-#{build_context.local_branch}"),
        ]
      end
    end

    def prepare
      ::Buildkite::Pipelines::Steps::Command.prepend(DockerBuild::Step)
    end

    dsl do
      def builder(ruby, compose: nil)
        build_context = context.extensions.find(BuildContext)
        build_context.ruby = ruby
        return unless build_context.ruby.build?

        command do
          compose_options = {
            build: "base",
            config: ".buildkite/docker-compose.yml",
            env: %w[PRE_STEPS RACK],
            "image-name" => build_context.ruby.image_name_for(build_context.build_id),
            "cache-from" => cache_from(build_context),
            push: build_push(build_context),
            "image-repository" => build_context.image_base,
          }
          compose_options.merge!(compose) if compose

          label ":docker: #{build_context.ruby.prefix}#{build_context.ruby.version}"
          key "docker-image-#{build_context.ruby.image_key}"
          plugin :artifacts, {
            download: ".dockerignore"
          }
          plugin :artifacts, {
            download: %w[
              .buildkite/.empty
              .buildkite/docker-compose.yml
              .buildkite/Dockerfile
              .buildkite/Dockerfile.beanstalkd
              .buildkite/mysql-initdb.d
              .buildkite/runner
            ],
            compressed: ".buildkite.tgz"
          }

          plugin :docker_compose, compose_options
          env({
            BUNDLER: build_context.bundler,
            RUBYGEMS: build_context.rubygems,
            RUBY_IMAGE: build_context.ruby.ruby_image,
            encrypted_0fb9444d0374_key: nil,
            encrypted_0fb9444d0374_iv: nil
          })

          timeout_in_minutes 15

          if build_context.ruby.soft_fail?
            soft_fail true
          end
          agents queue: build_context.build_queue
        end
      end
    end
  end
end
