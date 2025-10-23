# frozen_string_literal: true

require "json"

module Buildkite::Config
  module FetchPr
    class << self
      def title
        pr = JSON.parse(File.read(".buildkite/tmp/.pr-meta.json"))
        pr["title"]
      rescue
        ""
      end

      def filenames
        JSON
          .load_file(".buildkite/tmp/.pr-files.json")
          .map { |f| f["filename"] }
      rescue
        []
      end
    end
  end
end
