module Buildkite::Config
  class Generate
    STANDARD_QUEUES = [nil, "default", "builder"]

    attr_reader :build_queue
    attr_reader :run_queue
    attr_reader :image_base

    def initialize
      setup_queue

      @build_queue = ENV["BUILD_QUEUE"] || ENV["QUEUE"] || "builder"
      @run_queue = ENV["RUN_QUEUE"] || ENV["QUEUE"] || "default"
      @image_base = ENV["DOCKER_IMAGE"] || "973266071021.dkr.ecr.us-east-1.amazonaws.com/#{"#{build_queue}-" unless STANDARD_QUEUES.include?(build_queue)}builds"
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