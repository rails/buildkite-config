require "buildkite-builder"

module Buildkite::Config
  class RubyGroup < Buildkite::Builder::Extension
    def prepare
      context.data.ruby = {}
    end

    dsl do
      def ruby_group(ruby, &block)
        context.data.ruby[:version] = ruby

        group do
          label ruby

          yield if block_given?
        end
      end
    end
  end
end
