# frozen_string_literal: true

Buildkite::Builder.pipeline do
  require "buildkite_config"
  use Buildkite::Config::BuildContext

  plugin :docker, "docker#v5.10.0"
  plugin :artifacts, "artifacts#v1.9.3"
  plugin :secrets, "cluster-secrets#v1.0.0"

  build_context = context.extensions.find(Buildkite::Config::BuildContext)
  build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.3"))

  env CLOUDFLARE_PAGES_PROJECT: "rails-docs-preview"

  if build_context.rails_version < Gem::Version.new("7.2.x")
    command do
      label ":bk-status-passed: Build skipped"
      skip true
      command "true"
    end

    next
  end

  command do
    label "build", emoji: :rails
    key "build"
    command "bundle install && bundle exec rake preview_docs"
    timeout_in_minutes 15
    plugin :docker, {
      image: build_context.image_name_for("br-main", prefix: nil),
      environment: [
        "BUILDKITE_BRANCH",
        "BUILDKITE_BUILD_CREATOR",
        "BUILDKITE_BUILD_NUMBER",
        "BUILDKITE_BUILD_URL",
        "BUILDKITE_COMMIT",
        "BUILDKITE_MESSAGE",
        "BUILDKITE_PULL_REQUEST",
        "BUILDKITE_REPO",
      ],
    }
    plugin :artifacts, {
      upload: "preview.tar.gz"
    }
  end

  command do
    label "deploy", emoji: :rocket
    key "deploy"
    depends_on "build"
    timeout_in_minutes 15
    plugin :secrets, {
      env: "docs_preview_env"
    }
    plugin :docker, {
      environment: [
        "BUILDKITE_BRANCH",
        "CLOUDFLARE_PAGES_PROJECT",
        "CLOUDFLARE_ACCOUNT_ID",
        "CLOUDFLARE_API_TOKEN",
        # Turn off annoying prompt
        # "? Would you like to help improve Wrangler by sending usage metrics to Cloudflare? › (Y/n)"
        "WRANGLER_SEND_METRICS=false"
      ],
      image: "node:latest",
      mount_checkout: false,
      tty: false,
      volumes: ["./preview.tar.gz:/tmp/preview.tar.gz"],
      workdir: "/workdir"
    }
    plugin :artifacts, {
      download: "preview.tar.gz"
    }
    command "mkdir /tmp/preview"
    command "tar -xzf /tmp/preview.tar.gz -C /tmp/preview"
    command "npm install wrangler@3"
    command "npx wrangler@3 pages deploy /tmp/preview --project-name=\"$$CLOUDFLARE_PAGES_PROJECT\" --branch=\"$BUILDKITE_BRANCH\""
  end

  command do
    label "annotate", emoji: :writing_hand
    depends_on "deploy"
    timeout_in_minutes 15
    plugin :artifacts, {
      download: ".buildkite/bin/docs-preview-annotate",
      compressed: ".buildkite.tgz"
    }
    plugin :secrets, {
      env: "docs_preview_env"
    }
    command "sh -c \"$$ANNOTATE_COMMAND\" | buildkite-agent annotate --style info"
    # CLOUDFLARE_API_TOKEN is used to fetch preview URL from latest deployment
    env "ANNOTATE_COMMAND" => <<~ANNOTATE.gsub(/[[:space:]]+/, " ").strip
      docker run --rm
      -e CLOUDFLARE_ACCOUNT_ID
      -e CLOUDFLARE_API_TOKEN
      -e CLOUDFLARE_PAGES_PROJECT
      -v ./.buildkite:/workdir/.buildkite
      -w /workdir
      ruby:latest
      ruby .buildkite/bin/docs-preview-annotate
    ANNOTATE
  end
end
