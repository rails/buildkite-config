# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestRubyConfig < TestCase
  def test_class_methods
    assert_equal "rubylang/ruby:master-nightly-jammy", Buildkite::Config::RubyConfig.master_ruby
    assert_equal "yjit:#{Buildkite::Config::RubyConfig.master_ruby}", Buildkite::Config::RubyConfig.yjit_ruby
  end

  def test_constructor_defaults
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))

    assert_equal Gem::Version.new("3.2"), sub.version
    assert_not sub.yjit
    assert_nil sub.soft_fail
    assert_nil sub.image_base
  end

  def test_image_name
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_equal "3-2", sub.image_name
  end

  def test_image_name_for_default_suffix
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_equal ":3-2-build_id", sub.image_name_for
  end

  def test_image_name_for_image_base
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"), image_base: "base")
    assert_equal "base:3-2-suffix", sub.image_name_for("suffix")
  end

  def test_image_name_for_prefix
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"), prefix: "my-prefix:")
    assert_equal ":my-prefix-3-2-build_id", sub.image_name_for
  end

  def test_image_name_for_short
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_equal "3-2-build_id", sub.image_name_for(short: true)
  end

  def test_image_name_for_yjit
    sub = Buildkite::Config::RubyConfig.new(version: Buildkite::Config::RubyConfig.yjit_ruby)
    expected = Buildkite::Config::RubyConfig.master_ruby.gsub(/\W/, "-")
    assert_equal ":#{expected}-build_id", sub.image_name_for
  end

  def test_image_name_for_yjit_short
    sub = Buildkite::Config::RubyConfig.new(version: Buildkite::Config::RubyConfig.yjit_ruby)
    expected = Buildkite::Config::RubyConfig.master_ruby.gsub(/\W/, "-")
    assert_equal "#{expected}-build_id", sub.image_name_for(short: true)
  end

  def test_ruby_image_default
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_equal "3.2", sub.ruby_image
  end

  def test_ruby_image_yjit
    sub = Buildkite::Config::RubyConfig.new(version: Buildkite::Config::RubyConfig.yjit_ruby)
    assert_equal Buildkite::Config::RubyConfig.master_ruby, sub.ruby_image
  end

  def test_ruby_image_prefix
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"), prefix: "my-prefix:")
    assert_equal "my-prefix:3.2", sub.ruby_image
  end

  def test_short_ruby_default
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_equal "3.2", sub.short_ruby
  end

  def test_short_ruby_version
    sub = Buildkite::Config::RubyConfig.new(version: "ruby:2.7")
    assert_equal "2.7", sub.short_ruby
  end

  def test_short_ruby_master
    sub = Buildkite::Config::RubyConfig.new(version: Buildkite::Config::RubyConfig.master_ruby)
    assert_equal "master", sub.short_ruby
  end

  def test_short_ruby_yjit
    sub = Buildkite::Config::RubyConfig.new(version: Buildkite::Config::RubyConfig.yjit_ruby)
    assert_equal "yjit", sub.short_ruby
  end

  def test_short_ruby_sub
    sub = Buildkite::Config::RubyConfig.new(version: "ruby:2.7.2")
    assert_equal "2.7.2", sub.short_ruby
  end

  def test_soft_fail
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"), soft_fail: true)
    assert_predicate sub, :soft_fail?
  end

  def test_soft_fail_default
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_not sub.soft_fail?
  end

  def test_yjit_enabled
    sub = Buildkite::Config::RubyConfig.new(version: Buildkite::Config::RubyConfig.yjit_ruby)
    assert_predicate sub, :yjit_enabled?
  end

  def test_yjit_enabled_default
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_not sub.yjit_enabled?
  end

  def test_build
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), build: false)
    assert_not sub.build?
  end

  def test_build_default
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"))
    assert_predicate sub, :build?
  end

  def test_mangle_name
    sub = Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
    assert_equal "3-2", sub.send(:mangle_name, "3.2")
  end
end
