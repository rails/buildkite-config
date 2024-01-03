module Buildkite
  module Config
    autoload :Annotate, File.expand_path("buildkite_config/annotate", __dir__)
    autoload :Diff, File.expand_path("buildkite_config/diff", __dir__)
    autoload :Generate, File.expand_path("buildkite_config/generate", __dir__)
  end
end
