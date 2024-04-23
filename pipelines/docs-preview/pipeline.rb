# frozen_string_literal: true

Buildkite::Builder.pipeline do
  require "buildkite_config"
  use Buildkite::Config::BuildContext

  plugin :docker, "docker#v5.10.0"
  plugin :artifacts, "artifacts#v1.9.3"

  build_context = context.extensions.find(Buildkite::Config::BuildContext)
  build_context.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.3"))

  env CLOUDFLARE_PAGES_PROJECT: "rails-docs-preview"

  command do
    label "build", emoji: :rails
    key "build"
    command "bundle install && bundle exec rake preview_docs"
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
        "BUNDLE_WITHOUT=db:job:cable:storage:ujs",
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
      tty: false
    }
    plugin :artifacts, {
      download: "preview.tar.gz"
    }
    command "mkdir /tmp/preview"
    command "tar -xzf preview.tar.gz -C /tmp/preview"
    command "rm preview.tar.gz"
    command "npm install wrangler@3"
    command "npx wrangler@3 pages project create \"$$CLOUDFLARE_PAGES_PROJECT\" --production-branch=\"main\" || true"
    command "npx wrangler@3 pages deploy /tmp/preview --project-name=\"$$CLOUDFLARE_PAGES_PROJECT\" --branch=\"$BUILDKITE_BRANCH\""
  end

  command do
    label "annotate", emoji: :writing_hand
    depends_on "deploy"
    plugin :artifacts, {
      download: ".buildkite/bin/docs-preview-annotate",
      compressed: ".buildkite.tgz"
    }
    command "sh -c \"$$ANNOTATE_COMMAND\" | buildkite-agent annotate --style info"
    # CLOUDFLARE_API_TOKEN is used to fetch preview URL from latest deployment
    env "ANNOTATE_COMMAND" => <<~ANNOTATE.gsub(/[[:space:]]+/, " ").strip
      docker run --rm
      -v "$$PWD":/app:ro -w /app
      -e CLOUDFLARE_ACCOUNT_ID
      -e CLOUDFLARE_API_TOKEN
      -e CLOUDFLARE_PAGES_PROJECT
      ruby:latest
      ruby .buildkite/bin/docs-preview-annotate
    ANNOTATE
  end
end
