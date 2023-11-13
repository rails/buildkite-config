require "buildkite-builder"

module Buildkite::Config
  class RubyGroup < Buildkite::Builder::Extension
    dsl do
      def ruby_group(**args, &block)
        build_context = context.extensions.find(BuildContext)
        build_context.ruby = RubyConfig.new(**args)

        group do
          label args[:version]
          instance_eval(&block) if block_given?
        end
      end
    end
  end
end
