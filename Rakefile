# frozen_string_literal: true

require_relative "lib/buildkite_config"

require "minitest/test_task"
Minitest::TestTask.create
task default: [:test]

task :diff => [:buildkite_config, :rails] do
  diff = Buildkite::Config::Diff.compare
  puts diff.to_s(:color)

  annotate = Buildkite::Config::Annotate.new(diff)
  annotate.perform
end

task :buildkite_config do
  if !Dir.exist? "tmp/buildkite-config"
    `git clone --depth=1 https://github.com/rails/buildkite-config tmp/buildkite-config`
  else
    `cd tmp/buildkite-config && git pull origin main`
  end
end

task :rails do
  if !Dir.exist? "tmp/rails"
    `git clone --depth=1 https://github.com/rails/rails tmp/rails`
  else
    `cd tmp/rails && git pull origin main`
  end
end
