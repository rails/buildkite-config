# frozen_string_literal: true

require "buildkite-builder"

module Buildkite::Config
  class RakeCommand < Buildkite::Builder::Extension
    module Step
      def to_label(ruby, dir, task, suffix = nil)
        str = +"#{dir} #{task.split(/\s/).last.sub(/[:_]test|test:/, "")}"
        str.sub!(/ test/, "")
        return str unless ruby.version

        str << " (#{ruby.short_ruby})"
        return str unless suffix

        str << " #{suffix}"
      end

      def build_env(build_context, pre_steps, env)
        env ||= {}
        pre_steps ||= []

        env[:IMAGE_NAME] = build_context.image_name_for(build_context.build_id, prefix: nil)

        if build_context.ruby.yjit_enabled?
          env[:RUBY_YJIT_ENABLE] = "1"
        end

        if !(pre_steps).empty?
          env[:PRE_STEPS] = pre_steps.join(" && ")
        end

        env
      end

      def install_plugins(service = "default", env = nil, dir = ".", build_context:)
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

        if build_context.mainline
          plugin :secrets, {
            env: "main_env"
          }
        end

        compose_opts = {
          "env" => env,
          "run" => service,
          "config" => ".buildkite/docker-compose.yml",
          "shell" => ["runner", *dir],
          "tty" => "true",
        }

        if build_context.self_hosted?
          compose_opts["cli-version"] = "1"
          compose_opts["pull"] = service
          compose_opts["pull-retries"] = 3
        end

        plugin :docker_compose, compose_opts.compact
      end
    end

    def prepare
      ::Buildkite::Pipelines::Steps::Command.prepend(RakeCommand::Step)
    end

    dsl do
      def bundle(command, label:, env: nil)
        build_context = context.extensions.find(BuildContext)

        command do
          label label
          depends_on "docker-image-#{build_context.ruby.image_key}"
          command command

          install_plugins(build_context: build_context)

          env build_env(build_context, nil, env)

          agents queue: build_context.run_queue

          artifact_paths build_context.artifact_paths

          timeout_in_minutes build_context.timeout_in_minutes
        end
      end

      def rake(dir, task: "test", label: nil, service: "default", pre_steps: nil, env: nil, retry_on: nil, soft_fail: nil, parallelism: nil)
        build_context = context.extensions.find(BuildContext)

        if task.start_with?("mysql2:") || (build_context.rails_version >= Gem::Version.new("7.1.0.alpha") && task.start_with?("trilogy:"))
          task = "db:mysql:rebuild #{task}"
        elsif task.start_with?("postgresql:")
          task = "db:postgresql:rebuild #{task}"
        end

        command do
          label to_label(build_context.ruby, dir, task, label)
          depends_on "docker-image-#{build_context.ruby.image_key}"
          command "rake #{task}"

          install_plugins(service,  %w[PRE_STEPS RACK], dir, build_context: build_context)

          env build_env(build_context, pre_steps, env)

          agents queue: build_context.run_queue

          artifact_paths build_context.artifact_paths

          if retry_on ||= build_context.automatic_retry_on
            retry_on = [retry_on] unless retry_on.is_a?(Array)

            retry_on.each do |retry_rule|
              automatic_retry_on(**retry_rule)
            end
          end

          timeout_in_minutes build_context.timeout_in_minutes

          if soft_fail || build_context.ruby.soft_fail?
            soft_fail true
          end

          if parallelism
            parallelism parallelism
          end
        end
      end
    end
  end
end
