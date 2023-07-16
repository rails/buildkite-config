#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"

require_relative "../lib/buildkite_config"
require_relative "../lib/buildkite_config/diff"

diff = Buildkite::Config::Diff.new("pipeline-generate").compare

puts diff.to_s(:color)

File.open(ARGV.shift, "w") { |file| file.puts diff.to_s(:text) }