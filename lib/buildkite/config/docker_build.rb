# frozen_string_literal: true

require "buildkite-builder"

module Buildkite::Config
  class DockerBuild < Buildkite::Builder::Extension
    dsl do
      def builder(ruby:, &block)
        build_context = context.extensions.find(BuildContext)
        build_context.ruby = ruby
        return unless build_context.ruby.build?

        command do
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

          plugin :docker_compose, {
            build: "base",
            config: ".buildkite/docker-compose.yml",
            env: %w[PRE_STEPS RACK],
            "image-name" => build_context.ruby.image_name_for(build_context.build_id),
            "cache-from" => [
              build_context.rebuild_id && "base:" + build_context.image_base + ":" + build_context.ruby.image_name_for(build_context.rebuild_id),
              build_context.pull_request && "base:" + build_context.image_base + ":" + build_context.ruby.image_name_for("pr-#{build_context.pull_request}"),
              build_context.local_branch && build_context.local_branch !~ /:/ && "base:" + build_context.image_base + ":" + build_context.ruby.image_name_for("br-#{build_context.local_branch}"),
              build_context.base_branch && "base:" + build_context.image_base + ":" + build_context.ruby.image_name_for("br-#{build_context.base_branch}"),
              "base:" + build_context.image_base + ":" + build_context.ruby.image_name_for("br-main"),
            ].grep(String).uniq,
            push: [
              build_context.local_branch =~ /:/ ?
                "base:" + build_context.image_base + ":" + build_context.ruby.image_name_for("pr-#{build_context.pull_request}") :
                "base:" + build_context.image_base + ":" + build_context.ruby.image_name_for("br-#{build_context.local_branch}"),
            ],
            "image-repository" => build_context.image_base,
          }

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

          instance_exec(@attributes, &block) if block_given?
        end
      end
    end
  end
end
