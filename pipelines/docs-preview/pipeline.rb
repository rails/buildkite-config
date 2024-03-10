# frozen_string_literal: true

Buildkite::Builder.pipeline do
  plugin :docker, "docker#v5.10.0"
  plugin :artifacts, "artifacts#v1.9.3"

  command do
    label "build", emoji: :rails
    key "build"
    command "bundle install && bundle exec rake preview_docs"
    plugin :docker, {
      image: "ruby:latest",
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
        "CLOUDFLARE_ACCOUNT_ID",
        "CLOUDFLARE_API_TOKEN",
        # Turn off annoying prompt
        # "? Would you like to help improve Wrangler by sending usage metrics to Cloudflare? › (Y/n)"
        "WRANGLER_SEND_METRICS=false"
      ],
      image: "node:latest"
    }
    plugin :artifacts, {
      download: "preview.tar.gz"
    }
    command "tar -xzf preview.tar.gz"
    command "npm install wrangler"
    command "npx wrangler pages publish preview --project-name=$CLOUDFLARE_PAGES_PROJECT --branch=\"$BUILDKITE_BRANCH\""
  end

  command do
    label "annotate", emoji: :writing_hand
    depends_on "deploy"
    plugin :artifacts, { download: ".buildkite/docs-preview-annotate" }
    command "sh -c \"$$ANNOTATE_COMMAND\" | buildkite-agent annotate --style info"
    env "ANNOTATE_COMMAND" => <<~ANNOTATE.gsub(/[[:space:]]+/, " ").strip
      docker run --rm
      -v "$$PWD":/app:ro -w /app
      -e CLOUDFLARE_ACCOUNT_ID
      -e CLOUDFLARE_API_TOKEN
      -e CLOUDFLARE_PAGES_PROJECT
      ruby:latest
      ruby .buildkite/docs-preview-annotate
    ANNOTATE
  end
end
