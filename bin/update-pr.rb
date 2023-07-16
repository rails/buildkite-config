#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"

require_relative "../lib/buildkite_config"
require_relative "../lib/buildkite_config/pull_request"

pr = Buildkite::Config::PullRequest.new ARGF.read

pr.update

puts pr.body