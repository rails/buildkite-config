module Buildkite::Config
  class Generate
    STANDARD_QUEUES = [nil, "default", "builder"]

    attr_reader :build_queue
    attr_reader :run_queue
    attr_reader :image_base
    attr_reader :base_branch
    attr_reader :local_branch
    attr_reader :pull_request
    attr_reader :build_id
    attr_reader :rebuild_id
    attr_reader :root
    attr_reader :rails_version

    def initialize(root)
      setup_queue

      @root = Pathname.new(root)

      @build_queue = ENV["BUILD_QUEUE"] || ENV["QUEUE"] || "builder"
      @run_queue = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
      @image_base = ENV["DOCKER_IMAGE"] || "973266071021.dkr.ecr.us-east-1.amazonaws.com/#{"#{build_queue}-" unless STANDARD_QUEUES.include?(build_queue)}builds"
      @base_branch = ([ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"], ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
      @local_branch = ([ENV["BUILDKITE_BRANCH"], "main"] - [""]).first
      @pull_request = ([ENV["BUILDKITE_PULL_REQUEST"]] - ["false"]).first
      @build_id = ENV["BUILDKITE_BUILD_ID"]
      @rebuild_id = ([ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]] - [""]).first
      @rails_version = Gem::Version.new(File.read(@root.join("RAILS_VERSION")))
    end

    def mainline?
      local_branch == "main" || local_branch =~ /\A[0-9-]+(?:-stable)?\z/
    end

    def bundler
      case rails_version
      when Gem::Requirement.new("< 5.0")
        "< 2"
      when Gem::Requirement.new("< 6.1")
        "< 2.2.10"
      end
    end

    private

    def setup_queue
      # If the pipeline is running in a non-standard queue, default to
      # running everything in that queue.
      unless STANDARD_QUEUES.include?(ENV["BUILDKITE_AGENT_META_DATA_QUEUE"])
        ENV["QUEUE"] ||= ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
      end
    end
  end
end
