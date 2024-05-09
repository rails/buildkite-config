# frozen_string_literal: true

require "active_support"
require "active_support/dependencies/autoload"

module Buildkite
  module Config
    extend ActiveSupport::Autoload

    autoload :Annotate
    autoload :Diff
    autoload :DockerBuild
    autoload :BuildContext
    autoload :FetchPr
    autoload :RakeCommand
    autoload :RubyConfig
    autoload :RubyGroup
  end
end
