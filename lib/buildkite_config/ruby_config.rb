module Buildkite::Config
  class RubyConfig
    class << self
      # ONE_RUBY = "3.2"#RUBIES.last || SOFT_FAIL.last
      def one_ruby
        "3.2"
      end

      # MASTER_RUBY = "rubylang/ruby:master-nightly-jammy"
      def master_ruby
        "rubylang/ruby:master-nightly-jammy"
      end

      # Adds yjit: onto the master ruby image string so we
      # know when to turn on YJIT via the environment variable.
      # Same as master ruby, we want this to soft fail.
      # YJIT_RUBY = "yjit:#{MASTER_RUBY}"
      def yjit_ruby
        "yjit:#{master_ruby}"
      end
    end

    attr_reader :image_base, :version, :yjit
    def initialize(version: RubyConfig.one_ruby, image_base: nil)
      @image_base = image_base
      @version = version
      @yjit = @version == RubyConfig.yjit_ruby
    end

    def image_name
      @version.gsub(/\W/, "-")
    end

    def image_name_for(suffix = "build_id", short: false)
      tag = "#{mangle_name(ruby_image)}-#{suffix}"

      if short
        tag
      else
        "#{@image_base}:#{tag}"
      end
    end

    def ruby_image
      if @version == RubyConfig.yjit_ruby
        @version.sub("yjit:", "")
      else
        @version
      end
    end

    # A shortened version of the name for the Buildkite label.
    def short_ruby
      if @version == RubyConfig.master_ruby
        "master"
      elsif @version == RubyConfig.yjit_ruby
        "yjit"
      else
        @version.sub(/^ruby:|:latest$/, "")
      end
    end

    def yjit_enabled?
      @yjit
    end

    private
      def mangle_name(name)
        name.tr("^A-Za-z0-9", "-")
      end
  end
end
