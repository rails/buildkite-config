# frozen_string_literal: true

require "json"

module Buildkite::Config
  module FetchPr
    def self.title
      pr = JSON.parse(File.read(".buildkite/tmp/.pr-meta.json"))
      pr["title"]
    rescue
      ""
    end
  end
end
