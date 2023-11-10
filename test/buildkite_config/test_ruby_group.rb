# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestRubyGroup < TestCase
  def test_ruby_group
    pipeline = PipelineFixture.new do
      use Buildkite::Config::RubyGroup

      ruby_group "3.2" do
        command do
          label "test [#{pipeline.data.ruby[:version]}]]}]"
          command "rake test"
        end
      end
    end

    expected = {"steps"=>
      [{"label"=>"3.2",
        "group"=>nil,
        "steps"=>[{"label"=>"test [3.2]]}]", "command"=>["rake test"]}]}],
     "ruby"=>{"version"=>"3.2"}}
    assert_equal expected, pipeline.to_h
  end
end
