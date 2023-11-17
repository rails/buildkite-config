# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestRubyGroup < TestCase
  def test_ruby_group_default
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup

      ruby_group config: Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2")) do
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

      ruby_group config: Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), soft_fail: true) do
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

      ruby_group config: Buildkite::Config::RubyConfig.new(version: Gem::Version.new("1.8.7")) do
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

  def test_ruby_group_sets_image_base
    pipeline = PipelineFixture.new do
      build_context.ruby = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("2.0"))
      build_context.instance_variable_set(:@image_base, "test_ruby_group_sets_image_base")
      use Buildkite::Config::RubyGroup

      ruby_group config: build_context.ruby do
        bc = context.extensions.find(Buildkite::Config::BuildContext)

        command do
          label "test [#{bc.ruby.image_base}]"
          command "rake test"
        end
      end
    end

    expected = { "steps" =>
      [{ "label" => "2.0",
        "group" => nil,
        "steps" =>
         [{ "label" => "test [test_ruby_group_sets_image_base]",
           "command" => ["rake test"] }] }] }
    assert_equal expected, pipeline.to_h
  end
end
