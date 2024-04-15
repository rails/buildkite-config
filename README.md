# buildkite-config

This repository is home to the config which is used for Rails CI, that runs on [Buildkite](https://buildkite.com/rails/rails).

While Buildkite supports in-repo configuration inside the `.buildkite` directory, the main reason this repository exists is to support multiple stable branches of Rails with a single config.

There are a few pipelines supported in this project, you can find them all under the [pipelines](./pipelines/) directory.

* `buildkite-config`
  * Runs the tests, linter, and generates a diff of the pipelines in this repo for easy review
* `docs-preview`
  * Builds the API documentation and Guides and deploys them for review on PRs
* `rails-ci`
  * This is probably the main pipeline you care about
* `rails-nightly`
  * Runs the nightly jobs to test `rails/rails` against Ruby's `master` branch

Each pipeline has an `initial.yml` which is the config which is set in the Buildkite UI and acts as the entrypoint for a pipeline. We commit this file to make collaborating and reviewing changes easier.

We call these "initial steps".

Each pipeline will be in `pipelines/<pipeline>/pipeline.rb`, which is defined using the [Gusto/buildkite-builder](https://github.com/gusto/buildkite-builder) DSL.

The `pipeline.rb` file defines the rest of the pipeline dynamically using Ruby, and is generated inside of Docker during the "initial steps".

Unless there isn't one.

For example, in the case of `rails-ci-nightly` we simply re-use the main `rails-ci` pipeline and set an environment variable to change the behavior accordingly.

In `buildkite-config`, there are steps to run tests and lint, but there is no need for a dynamic pipeline. Instead, we trigger a `rails-ci` pipeline using the config from that version (e.g. a PR).


## Design

There are some specific design decisions to be aware of when making changes to this project.

### Initial Steps

First, the "initial steps" are designed to run on the host where the `buildkite-agent` is available, but any other code is run inside a Docker container with limited access to specific directories.

For example when `rails-ci` is running a Rake task, like the Active Record tests, it will run inside Docker.

Even generating the rest of the pipeline dynamically is run inside Docker.

This is to prevent anyone submitting a PR to `rails/rails` and having full access to the host in CI.

We keep the "initial steps" baked in the Buildkite UI where only committers are allowed to change them for this reason.


### Rails CI

Since this is arguably the most important pipeline, let's cover it.

This pipeline makes heavy use of Docker, so it's recommended to familiarize yourself with the [docker-compose.yml](./docker-compose.yml).

Inside the compose project, there are multiple services.

* `base`: is the main service used to build the base Docker image
* `default`: runs most of the frameworks tests except for those which need a database
* `railties`: needs multiple databases and services
* `mysql`: for running Active Record tests against a MySQL database
* etc, etc

When a build is triggered for `rails/rails` there are essentially a few steps.

1. Buildkite creates a build of the pipeline using the "initial steps" and waits for an agent
2. After acquiring an agent, Buildkite checks out the repo and setups up the workspace
3. The "initial steps" are then executed, cloning the `buildkite-config` repo inside `.buildkite`
4. On the host, issue a `docker run` command to generate the pipeline
5. The generated pipeline is piped back to the host where the `buildkite-agent` uploads it to continue

The final step to generate a pipeline uses the [bin/pipeline-generate](./bin/pipeline-generate) command, which uses the `buildkite-builder` CLI to compile the pipeline and output the YAML configuration Buildkite uses to continue the build.

This pipeline is defined under [pipelines/rails-ci/pipeline.rb](./pipelines/rails-ci/pipeline.rb).

#### Pipeline DSL

The original version of the `rails-ci` pipeline was [one big script](https://github.com/rails/buildkite-config/blob/a8538b98963711537115ee8b736770123e88c56d/pipeline-generate), and while it did the job very well, making changes and understanding what it was doing were difficult.

We were able to reduce the pipeline by about 65%, while abstracting the complexity into a few separate modules.

The `rails-ci` pipeline boils down to essentially the following:

* Decide the subset of rubies we want to use
  * For nightly builds: use master, yjit, etc
  * For main and PRs: select from a range based current Rails checkout
    * The minimum version is based on the `required_ruby_version` field from `rails.gemspec`
    * The max is optionally defined for older versions of Rails
* Create a `build` group for each Ruby that needs to be built
* For each version of Ruby create a new group
  * In each group, there is a step for each framework (actionpack, activerecord, etc)
    * Set the directory to run `rake test` in and any additional configuration
* For the `default_ruby`, the highest stable version (not marked soft_fail)
  * Run the isolated tests for each framework that needs
  * These tests basically run each test file in a separate process to de-risk any determinism bugs

Let's go over the parts of the DSL that make this possible.

##### `BuildContext`

This [module](./lib/buildkite/config/build_context.rb) stores all of the knowledge we care about when generating a pipeline.

* Which version of Rails are we building against?
* Which version of Ruby are we targeting?
* What branch are we on?

As well as several defaults we use for every step, like timeout and retry policy.

Basically, if there is an environment variable we use within the pipeline, this is place to find them.

##### `DockerBuild`

At the start of each build, we use a [builder](./lib/buildkite/config/docker_build.rb) for each version of Ruby we use in CI.

* First pull the `.dockerignore` and relevant `Dockerfile` files from artifacts that were uploaded during pipeline generation
* Using the [docker-compose plugin](https://github.com/buildkite-plugins/docker-compose-buildkite-plugin) build the "base" service
* Set the `image-name` to the Ruby version and the `build_id` from the build context
* Set the `image-repository` to the ECR repository which hosts the build images
* Set `cache-from` to the latest image build from ECR, either the PR branch or fall back to main
* Set the `push` to update the image on ECR for the branch

We also pass in a few environment variables.

* `BUNDLER` and `RUBYGEMS` if we need to override it, like for older rubies
* `RUBY_IMAGE` is the base ruby image tag from [Docker Hub](https://hub.docker.com/_/ruby)
* `encrypted_*_key` and `encrypted_*_iv` are used to decrypt secrets for Active Storage integration test configurations

Then we set a default timeout of 15 minutes, and allow the step to soft fail if the version of Ruby is non-critical (e.g. master builds).

Lastly, we set the agent queue to use our build queue provided by Buildkite which is optimized for building our Docker images.

##### `RakeCommand`

For each framework in Rails, we want to create a step that runs the tests inside of Docker.

This is the purpose of the `rake` step, it abstracts the [command step](https://buildkite.com/docs/pipelines/command-step) in Buildkite.

* Set the label to show the framework, task, and appropriate version of Ruby
* Create a dependency on the Docker image build step defined by `DockerBuild`
* Similar to `builder`, pull the artifacts for Docker needed to run containers
* Set the `run` to the appropriate service defined in the `docker-compose.yml`
* Set the `shell` command to execute the [runner](./runner) script inside the framework directory

Additionally, we pass `PRE_STEPS` to run any additional Rake tasks or commands before running tests. Currently, we also pass in the `RACK` environment variable so that we can test against different versions of Rack (v2, v3, or head).

Each `rake` step is set to use the run queue which will request any agent available to run tests.

There are optional parameters for calling this step to override the defaults like timeout, retry policy, failure policy, and parallelism.

##### `RubyGroup`

Lastly, a `ruby_group` is an abstraction of a [group step](https://buildkite.com/docs/pipelines/group-step) in Buildkite.

The purpose of this step is to visually separate each version of supported Ruby in the Buildkite UI.

* Set the label of the group step to the currently activated Ruby version
* Update the build context with that version of Ruby
* Evaluate the rest of the group's steps

##### Wrap up

Now you should have a decent understanding of how this pipeline runs and where it is defined.

If you have any questions or suggestions for improvements, feel free to reach out.

## Running Locally

When you need to investigate things on your machine, there are a couple of steps.

1. You need a checkout of `rails/rails`
2. Inside that checkout you need a clone of `rails/buildkite-config`
3. Then you need to build the base docker image
4. Finally you can run tasks inside the docker container

For example, we will use a clean checkout of `rails/rails` but this could be your own fork.

```
# Create a Tmp dir and change to it
cd `mktemp -d`

# Make a shallow clone of Rails
git clone --depth=1 https://github.com/rails/rails

# Ensure the working directory is the Rails checkout
cd rails

# Clone the buildkite-config repo
git clone https://github.com/rails/buildkite-config .buildkite
```

With your directories in place, you can now proceed to step 3, building the base image.

We'll use a Ruby version 3.3 image for the base.

```
RUBY_IMAGE="ruby:3.3" docker-compose -f .buildkite/docker-compose.yml build base
```

NOTE: any changes your make to your Rails checkout will have to repeat the build process.

As of writing this, because the Dockerfile is using `ADD` to copy the checkout rather than using a mounted volume.

Now you can run tasks inside the docker container.

For example, if we wanted to run the Active Record tests for SQLite3.

```
IMAGE_NAME=buildkite-base RUBY_IMAGE=ruby:3.3 docker-compose -f .buildkite/docker-compose.yml run default runner activerecord 'rake sqlite3:test'
```


## Contributing

When you're ready to make changes to `buildkite-config`, there are a few things to know.

### Testing and Linting

There are a number of tests for the DSL, that are run for each change to the repo in CI. You can run them yourself:

```
bundle exec rake test
```

We also re-use many of the `rails/rails` rubocop rules that are defined in the [.rubocop.yml](./.rubocop.yml), this is of course subject to change.

CI will also run rubocop, but in case you make an error or want to update the rules, you can run it yourself too.

```
bundle exec rubocop
```

### Submitting PRs

When you open a PR to `rails/buildkite-config` a Buildkite pipeline is triggered, but requires approval before execution.

During CI, there are steps to trigger downstream `rails-ci` pipelines using the supplied configuration. In order to avoid impacting capacity and to minimize abuse a member of the Rails organization, such as a committer, is required to approve those steps.

However, steps for running tests, linter, and diff do not require approval.

### Checking the diff

The final "result" of `pipeline-generate` is a YAML blob of configuration which is understood by Buildkite.

Since this result is simply YAML, we can generate the pipeline on the current working branch and compare that to a generated pipeline on main.

This process is defined in [Buildkite::Config::Diff](./lib/buildkite/config/diff.rb).

During CI, we use this process to compare the changes to the generated pipeline and create an [annotation](https://buildkite.com/docs/agent/v3/cli-annotate) on the build for reviewers.

You can also generate this diff locally, in order to save cycles and get faster feedback.

```
bundle exec rake diff
```

### Getting feedback

If you PR is waiting for review, please follow the [standard practices](https://edgeguides.rubyonrails.org/contributing_to_ruby_on_rails.html#get-some-feedback) to move things along.


## Committers

Note, that this information is mainly for committers and members of the Rails organization.

For some operations, like triggering rebuilds, cancelling, and modifying settings require you have a Buildkite account.

This account must be associated with your GitHub account, which you can authorize at [buildkite.com/sso/rails](https://buildkite.com/sso/rails).


### Updating the Initial Steps

As of writing, the initial steps defined in the Buildkite UI are not automatically updated upon merge.

We do have the [bin/update-initial-pipelines](./bin/update-initial-pipelines) script to help with this.

1. Create an [API token](https://buildkite.com/docs/apis/managing-api-tokens) for your Buildkite account
2. Make sure your token has `write_pipelines` scope
3. Store the token inside the `$BUILDKITE_TOKEN` environment variable

If you're using `dotenv` you can copy the `.envrc.sample` and update the token there.

```
cp .envrc.sample .envrc`
sed -i -E "s/changeme/$BUILDKITE_TOKEN/g" .envrc
direnv allow
```

### Triggering builds with custom Initial Steps

There are cases when you want to verify changes to the initial steps of a pipeline.

In this case the [bin/trigger-pipeline](./bin/trigger-pipeline) script is available.

Follow the steps for setting up a `$BUILDKITE_TOKEN` above in [Updating the Initial Steps](#updating-the-initial-steps).

Make sure your token has `write_builds` scope!

See the Buildkite docs for [token scopes](https://buildkite.com/docs/apis/managing-api-tokens#token-scopes) if you'd like to know more.

#### `buildkite-config/initial` from a fork PR

This requires having opened a PR against `rails/buildkite-config` from a fork.

```
bin/trigger-pipeline --pr 91 --fork zzak --branch "zzak:refactor-nightly" rails buildkite-config
```

That will trigger a build of the [`buildkite-config` pipeline](https://buildkite.com/rails/buildkite-config) and checkout the fork "zzak/buildkite-config" with the branch "refactor-nightly", based on the PR number 91.

This ensures the upstream knows about the pull request repo and base branch.

It will use the current [pipelines/buildkite-config/initial.yml](./pipelines/buildkite-config/initial.yml) file from your current working directory, even if it is not committed.

#### `buildkite/rails-ci`

As of writing this, the `buildkite-config` pipeline can only trigger a `rails-ci` pipeline using the existing intial steps from the Buildkite UI.

In the event you want to test your changes to [pipelines/rails-ci/initial.yml](./pipelines/rails-ci/initial.yml) from your current working directory, you can use this script.

```
bin/trigger-pipeline --fork zzak --config_branch "zzak:refactor-nightly" rails rails-ci
```

This will trigger a build of the [`rails-ci` pipeline](https://buildkite.com/rails/rails-ci) using the config from a fork and branch, using those initial steps.

If you change the pipeline slug, you can also test the [`rails-ci-nightly pipeline](https://buildkite.com/rails/rails-ci-nightly) like so:

```
bin/trigger-pipeline --fork zzak --config_branch "zzak:refactor-nightly" rails rails-ci-nightly
```

Just note that these pipelines will be triggered to use the `main` branch of `rails/rails` unless you specify a `--branch` or `--commit` flag.

```
bin/trigger-pipeline --branch "debug-ci" rails rails-ci
```

There are room for improvements, and in most cases you can get by just using the [Buildkite UI](https://buildkite.com/docs/pipelines/dashboard-walkthrough) to trigger builds.



