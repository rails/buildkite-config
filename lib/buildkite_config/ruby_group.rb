require "buildkite-builder"

module Buildkite::Config
  class RubyGroup < Buildkite::Builder::Extension
    dsl do
      def ruby_group(config:nil, **args, &block)
        build_context = context.extensions.find(BuildContext)
        if config.nil?
          build_context.ruby = RubyConfig.new(**args)
        else
          build_context.ruby = config
        end
        build_context.ruby.image_base = build_context.image_base

        group do
          label build_context.ruby.version.to_s
          instance_eval(&block) if block_given?
        end
      end
    end
  end
end
