# frozen_string_literal: true

module Buildkite::Config
  class RubyConfig
    class << self
      # MASTER_RUBY = "rubylang/ruby:master-nightly-jammy"
      def master_ruby
        "rubylang/ruby:master-nightly-jammy"
      end

      def yjit_ruby
        # Adds yjit: onto the master ruby image string so we
        # know when to turn on YJIT via the environment variable.
        new(version: "yjit:#{master_ruby}", soft_fail: true, yjit: true)
      end
    end

    attr_accessor :soft_fail
    attr_reader :version, :yjit, :prefix
    def initialize(version:, soft_fail: nil, prefix: nil, yjit: false)
      @prefix = prefix
      @version = version
      @yjit = yjit
      @build = !yjit

      if soft_fail
        @soft_fail = soft_fail
      end
    end

    def image_key
      ruby_image.gsub(/\W/, "-")
    end

    def image_name_for(suffix = "build_id", short: false)
      "#{mangle_name(ruby_image)}-#{suffix}"
    end

    def ruby_image
      if yjit_enabled?
        @version.sub("yjit:", "")
      else
        "#{@prefix}#{@version}"
      end
    end

    # A shortened version of the name for the Buildkite label.
    def short_ruby
      if @version == RubyConfig.master_ruby
        "master"
      elsif yjit_enabled?
        "yjit"
      else
        @version.to_s.sub(/^ruby:|:latest$/, "")
      end
    end

    def build?
      @build
    end

    def soft_fail?
      @soft_fail
    end

    def yjit_enabled?
      @yjit
    end

    private
      def mangle_name(name)
        name.to_s.tr("^A-Za-z0-9", "-")
      end
  end
end
