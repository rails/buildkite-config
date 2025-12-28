# frozen_string_literal: true

require "json"
require "uri"

module Buildkite::Config
  module FetchPr
    extend self

    def title
      @title ||= if pull_request_number
        begin
          response = http.get("/repos/#{github_repo}/pulls/#{pull_request_number}")
          pr = JSON.parse(response.body)
          pr["title"]
        rescue => error
          $stderr.puts("Failed to fetch PR title: #{error}")
          ""
        end
      else
        ""
      end
    end

    def filenames
      @filenames ||= if pull_request_number
        begin
          response = http.get("/repos/#{github_repo}/pulls/#{pull_request_number}/files")
          pr = JSON.parse(response.body)
          pr.map { |f| f["filename"] }
        rescue => error
          $stderr.puts("Failed to fetch PR files: #{error}")
          []
        end
      else
        []
      end
    end

    private
      def pull_request_number
        Integer(ENV["BUILDKITE_PULL_REQUEST"], exception: false)
      end

      def github_repo
        ENV.fetch("BUILDKITE_REPO")[%r{github\.com[/:](.+?)(?:\.git)?\z}, 1]
      end

      def http
        @http ||= Net::HTTP.start("api.github.com", use_ssl: true)
      end
  end
end
