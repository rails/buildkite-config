# frozen_string_literal: true

require "buildkite-builder"

module Buildkite::Config
  class RubyGroup < Buildkite::Builder::Extension
    dsl do
      def ruby_group(config, &block)
        build_context = context.extensions.find(BuildContext)
        build_context.ruby = config

        group do
          label build_context.ruby.version.to_s
          instance_eval(&block) if block_given?
        end
      end
    end
  end
end
