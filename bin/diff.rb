#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"

require_relative "../lib/buildkite_config"

diff = Buildkite::Config::Diff.new("pipeline-generate").compare

puts diff.to_s(:color)

pr = Buildkite::Config::PullRequest.new diff.to_s(:text)

pr.update

puts pr.body
