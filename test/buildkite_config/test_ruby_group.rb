# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestRubyGroup < TestCase
  def test_ruby_group_default
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup

      ruby_group Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2")) do
        build_context = context.extensions.find(Buildkite::Config::BuildContext)

        command do
          label "test [#{build_context.ruby.version}]]}]"
          command "rake test"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "3.2",
        "group" => nil,
        "steps" => [{ "label" => "test [3.2]]}]", "command" => ["rake test"] }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_soft_fail
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup

      ruby_group Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), soft_fail: true) do
        build_context = context.extensions.find(Buildkite::Config::BuildContext)

        command do
          label "test [#{"soft_fail" if build_context.ruby.soft_fail?}]]}]"
          command "rake test"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "3.3",
        "group" => nil,
        "steps" => [{ "label" => "test [soft_fail]]}]", "command" => ["rake test"] }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_ruby_group_config_version
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup

      ruby_group Buildkite::Config::RubyConfig.new(version: Gem::Version.new("1.8.7")) do
        command do
          label "test"
          command "rake test"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "1.8.7",
        "group" => nil,
        "steps" => [{ "label" => "test", "command" => ["rake test"] }] }] }
    assert_equal expected, pipeline.to_h
  end

  def test_ruby_group_yjit
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup
      yjit = Buildkite::Config::RubyConfig.yjit_ruby

      ruby_group yjit do
        build_context = context.extensions.find(Buildkite::Config::BuildContext)

        command do
          label "test [#{build_context.ruby.short_ruby}]"
          command "rake test"
          depends_on "docker-image-#{build_context.ruby.image_key}"
        end
      end
    end

    assert_equal({ "steps" =>
      [{ "label" => "yjit:rubylang/ruby:master-nightly-jammy",
         "group" => nil,
         "steps" =>
         [{ "label" => "test [yjit]",
            "command" => ["rake test"],
            "depends_on" => ["docker-image-rubylang-ruby-master-nightly-jammy"] }] }] }, pipeline.to_h)
  end
end
