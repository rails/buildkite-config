module Buildkite
  module Config
    autoload :Diff, "./buildkite_config/diff"
    autoload :PullRequest, "./buildkite_config/pull_request"
  end
end