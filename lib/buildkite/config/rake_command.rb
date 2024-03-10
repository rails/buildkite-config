# frozen_string_literal: true

require "buildkite-builder"

module Buildkite::Config
  class RakeCommand < Buildkite::Builder::Extension
    dsl do
      def to_label(ruby, dir, task)
        str = +"#{dir} #{task.sub(/[:_]test|test:/, "")}"
        str.sub!(/ test/, "")
        return str unless ruby.version

        str << " (#{ruby.short_ruby})"
      end

      def rake(dir = "", task = "test", service: "default", pre_steps: [], &block)
        build_context = context.extensions.find(BuildContext)

        _label = to_label(build_context.ruby, dir, task)

        ## Setup ENV
        _env = {
          IMAGE_NAME: build_context.image_base + ":" + build_context.ruby.image_name_for(build_context.build_id)
        }

        if task.start_with?("mysql2:") || (build_context.rails_version >= Gem::Version.new("7.1.0.alpha") && task.start_with?("trilogy:"))
          task = "db:mysql:rebuild #{task}"
        elsif task.start_with?("postgresql:")
          task = "db:postgresql:rebuild #{task}"
        end

        if build_context.rails_version < Gem::Version.new("5.x")
          _env["MYSQL_IMAGE"] = "mysql:5.6"
        elsif build_context.rails_version < Gem::Version.new("6.x")
          _env["MYSQL_IMAGE"] = "mysql:5.7"
        end

        if build_context.rails_version < Gem::Version.new("5.2.x")
          _env["POSTGRES_IMAGE"] = "postgres:9.6-alpine"
        end

        if build_context.ruby.yjit_enabled?
          _env[:RUBY_YJIT_ENABLE] = "1"
        end

        if !(pre_steps).empty?
          _env[:PRE_STEPS] = pre_steps.join(" && ")
        end

        command do
          label _label
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
            "run" => service,
            "pull" => service,
            "config" => ".buildkite/docker-compose.yml",
            "shell" => ["runner", dir],
          }

          env _env
          agents queue: build_context.run_queue
          artifact_paths build_context.artifact_paths
          automatic_retry_on(**build_context.automatic_retry_on)
          timeout_in_minutes build_context.timeout_in_minutes

          if build_context.ruby.soft_fail?
            soft_fail true
          end

          instance_exec([@attributes, build_context], &block) if block_given?
        end
      end
    end
  end
end
