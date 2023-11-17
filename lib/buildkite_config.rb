# frozen_string_literal: true

module Buildkite
  module Config
    autoload :Annotate, File.expand_path("buildkite_config/annotate", __dir__)
    autoload :Diff, File.expand_path("buildkite_config/diff", __dir__)
    autoload :DockerBuild, File.expand_path("buildkite_config/docker_build", __dir__)
    autoload :BuildContext, File.expand_path("buildkite_config/build_context", __dir__)
    autoload :RakeCommand, File.expand_path("buildkite_config/rake_command", __dir__)
    autoload :RubyConfig, File.expand_path("buildkite_config/ruby_config", __dir__)
    autoload :RubyGroup, File.expand_path("buildkite_config/ruby_group", __dir__)
  end
end
