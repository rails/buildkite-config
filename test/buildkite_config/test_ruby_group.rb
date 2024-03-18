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
          label "test [#{build_context.ruby.version}]"
          command "rake test"
        end
      end
    end

    assert_equal "3.2", pipeline.to_h["steps"][0]["label"]
    assert_equal "test [3.2]", pipeline.to_h["steps"][0]["steps"][0]["label"]
  end

  def test_soft_fail
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup

      ruby_group Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), soft_fail: true) do
        build_context = context.extensions.find(Buildkite::Config::BuildContext)

        command do
          label "test [#{"soft_fail" if build_context.ruby.soft_fail?}]"
          command "rake test"
        end
      end
    end

    assert_equal "3.3", pipeline.to_h["steps"][0]["label"]
    assert_equal "test [soft_fail]", pipeline.to_h["steps"][0]["steps"][0]["label"]
  end


  def test_ruby_group_yjit
    yjit = Buildkite::Config::RubyConfig.yjit_ruby

    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup

      ruby_group yjit do
        build_context = context.extensions.find(Buildkite::Config::BuildContext)

        command do
          label "test [#{build_context.ruby.short_ruby}]"
          command "rake test"
          depends_on "docker-image-#{build_context.ruby.image_key}"
        end
      end
    end

    assert_equal yjit.version, pipeline.to_h["steps"][0]["label"]
    assert_equal "test [yjit]", pipeline.to_h["steps"][0]["steps"][0]["label"]
    assert_includes pipeline.to_h["steps"][0]["steps"][0], "depends_on"
    assert_equal "docker-image-#{yjit.image_key}", pipeline.to_h["steps"][0]["steps"][0]["depends_on"][0]
  end
end
