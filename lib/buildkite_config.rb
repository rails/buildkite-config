module Buildkite
  module Config
    autoload :Annotate, File.expand_path("buildkite_config/annotate", __dir__)
    autoload :Diff, File.expand_path("buildkite_config/diff", __dir__)
    autoload :DockerBuild, File.expand_path("buildkite_config/docker_build", __dir__)
    autoload :DockerCompose, File.expand_path("buildkite_config/docker_compose", __dir__)
    autoload :Context, File.expand_path("buildkite_config/context", __dir__)
  end
end
