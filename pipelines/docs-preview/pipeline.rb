# frozen_string_literal: true

Buildkite::Builder.pipeline do
  require "buildkite_config"
  use Buildkite::Config::BuildContext
  use Buildkite::Config::DockerBuild

  plugin :docker, "docker#v5.10.0"
  plugin :docker_compose, "docker-compose#v5.12.1"
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

  builder build_context.ruby

  command do
    label "build", emoji: :rails
    depends_on "docker-image-#{build_context.ruby.image_key}"
    key "build"
    timeout_in_minutes 15
    # The PR's code runs here, so it gets no writable mount of the host
    # checkout: a .git/config it wrote would run on the host at a later git
    # command. It uses the source baked into the image, reads .git only for
    # `git rev-parse HEAD`, and returns the tarball on stdout. The rm stops the
    # redirect from following a preview.tar.gz symlink committed in the PR.
    command <<~COMMAND.gsub(/[[:space:]]+/, " ").strip
      rm -f preview.tar.gz &&
      docker run --rm --init
      -v ./.git:/rails/.git:ro
      -e GIT_CONFIG_COUNT=1
      -e GIT_CONFIG_KEY_0=safe.directory
      -e GIT_CONFIG_VALUE_0=/rails
      -e BUILDKITE_BRANCH
      -e BUILDKITE_BUILD_CREATOR
      -e BUILDKITE_BUILD_NUMBER
      -e BUILDKITE_BUILD_URL
      -e BUILDKITE_COMMIT
      -e BUILDKITE_MESSAGE
      -e BUILDKITE_PULL_REQUEST
      -e BUILDKITE_REPO
      #{build_context.image_name_for(build_context.build_id, prefix: nil)}
      sh -c 'bundle install >&2 && bundle exec rake preview_docs >&2 && cat preview.tar.gz'
      > preview.tar.gz
    COMMAND
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
      ruby:4.0
      ruby .buildkite/bin/docs-preview-annotate
    ANNOTATE
  end
end
