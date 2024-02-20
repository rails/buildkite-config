# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "buildkite_config"

require "minitest/test_task"
Minitest::TestTask.create
task default: [:test]

task :diff, [:nightly] => [:buildkite_config, :rails] do |_, args|
  args.with_defaults(nightly: false)

  diff = Buildkite::Config::Diff.compare(nightly: args[:nightly])
  annotate = Buildkite::Config::Annotate.new(diff, nightly: args[:nightly])
  puts annotate.plan
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
