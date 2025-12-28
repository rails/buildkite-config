# frozen_string_literal: true

module Buildkite
  module Config
    autoload :Annotate, "buildkite/config/annotate.rb"
    autoload :Diff, "buildkite/config/diff.rb"
    autoload :DockerBuild, "buildkite/config/docker_build.rb"
    autoload :BuildContext, "buildkite/config/build_context.rb"
    autoload :FetchPr, "buildkite/config/fetch_pr.rb"
    autoload :RakeCommand, "buildkite/config/rake_command.rb"
    autoload :RubyConfig, "buildkite/config/ruby_config.rb"
    autoload :RubyGroup, "buildkite/config/ruby_group.rb"
  end
end
