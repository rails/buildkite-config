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

        env[:IMAGE_NAME] = build_context.image_base + ":" + build_context.ruby.image_name_for(build_context.build_id)

        if build_context.ruby.yjit_enabled?
          env[:RUBY_YJIT_ENABLE] = "1"
        end

        if !(pre_steps).empty?
          env[:PRE_STEPS] = pre_steps.join(" && ")
        end

        env
      end
    end

    def prepare
      ::Buildkite::Pipelines::Steps::Command.prepend(RakeCommand::Step)
    end

    dsl do
      def rake(dir, options = {})
        build_context = context.extensions.find(BuildContext)
        task = options[:task] || "test"

        if task.start_with?("mysql2:") || (build_context.rails_version >= Gem::Version.new("7.1.0.alpha") && task.start_with?("trilogy:"))
          task = "db:mysql:rebuild #{task}"
        elsif task.start_with?("postgresql:")
          task = "db:postgresql:rebuild #{task}"
        end

        command do
          label to_label(build_context.ruby, dir, task, options[:label])
          depends_on "docker-image-#{build_context.ruby.image_key}"
          command "rake #{task}"

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
            "env" => %w[PRE_STEPS RACK],
            "run" => options[:service] || "default",
            "pull" => options[:service] || "default",
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", dir],
          }

          env build_env(build_context, options[:pre_steps], options[:env])

          agents options[:agents] || { queue: build_context.run_queue }

          artifact_paths options[:artifact_paths] || build_context.artifact_paths

          if options[:retry_on]
            automatic_retry_on(**options[:retry_on])
          else
            automatic_retry_on(**build_context.automatic_retry_on)
          end

          timeout_in_minutes options[:timeout_in_minutes] || build_context.timeout_in_minutes

          if options[:soft_fail] || build_context.ruby.soft_fail?
            soft_fail true
          end

          if options[:parallelism]
            parallelism options[:parallelism]
          end
        end
      end
    end
  end
end
