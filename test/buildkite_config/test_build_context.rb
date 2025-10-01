# frozen_string_literal: true

require "test_helper"
require "buildkite_config"

class TestBuildContext < TestCase
  def create_build_context
    Buildkite::Config::BuildContext.new("context")
  end

  def test_initializer
    sub = create_build_context
    assert_not_nil sub
  end

  def test_ci_env_buildkite
    @before_env_buildkite = ENV["BUILDKITE"]
    ENV["BUILDKITE"] = "true"

    sub = create_build_context
    assert_predicate sub, :ci?
  ensure
    ENV["BUILDKITE"] = @before_env_buildkite
  end

  def test_ci_env_ci
    @before_env_ci = ENV["CI"]
    ENV["CI"] = "true"

    sub = create_build_context
    assert_predicate sub, :ci?
  ensure
    ENV["CI"] = @before_env_ci
  end

  def test_ci_env_compute_type_nil
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV.delete("BUILDKITE_COMPUTE_TYPE")

    sub = create_build_context
    assert_predicate sub, :self_hosted?
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
  end

  def test_ci_env_compute_type_self_hosted
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV["BUILDKITE_COMPUTE_TYPE"] = "self-hosted"

    sub = create_build_context
    assert_predicate sub, :self_hosted?
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
  end

  def test_ci_env_compute_type_hosted
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV["BUILDKITE_COMPUTE_TYPE"] = "hosted"

    sub = create_build_context
    assert_predicate sub, :hosted?
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
  end

  def test_nightly
    @before_env_nightly = ENV["RAILS_CI_NIGHTLY"]
    ENV["RAILS_CI_NIGHTLY"] = "true"

    sub = create_build_context
    assert_predicate sub, :nightly?
  ensure
    ENV["RAILS_CI_NIGHTLY"] = @before_env_nightly
  end

  def test_nightly_false
    @before_env_nightly = ENV["RAILS_CI_NIGHTLY"]
    ENV["RAILS_CI_NIGHTLY"] = nil

    sub = create_build_context
    assert_not_predicate sub, :nightly?
  ensure
    ENV["RAILS_CI_NIGHTLY"] = @before_env_nightly
  end

  def test_skip_ci_skip
    @before_env_buildkite_message = ENV["BUILDKITE_MESSAGE"]
    ENV["BUILDKITE_MESSAGE"] = "[ci skip] test_skip"

    sub = create_build_context
    assert_predicate sub, :skip?
  ensure
    ENV["BUILDKITE_MESSAGE"] = @before_env_buildkite_message
  end

  def test_skip_ci
    @before_env_buildkite_message = ENV["BUILDKITE_MESSAGE"]
    ENV["BUILDKITE_MESSAGE"] = "[skip ci] test_skip"

    sub = create_build_context
    assert_predicate sub, :skip?
  ensure
    ENV["BUILDKITE_MESSAGE"] = @before_env_buildkite_message
  end

  def test_skip_ci_dash_skip
    @before_env_buildkite_message = ENV["BUILDKITE_MESSAGE"]
    ENV["BUILDKITE_MESSAGE"] = "[ci-skip] test_skip"

    sub = create_build_context
    assert_predicate sub, :skip?
  ensure
    ENV["BUILDKITE_MESSAGE"] = @before_env_buildkite_message
  end

  def test_skip_skip_dash_ci
    @before_env_buildkite_message = ENV["BUILDKITE_MESSAGE"]
    ENV["BUILDKITE_MESSAGE"] = "[skip-ci] test_skip"

    sub = create_build_context
    assert_predicate sub, :skip?
  ensure
    ENV["BUILDKITE_MESSAGE"] = @before_env_buildkite_message
  end

  def test_skip_false
    @before_env_buildkite_message = ENV["BUILDKITE_MESSAGE"]
    ENV["BUILDKITE_MESSAGE"] = "not a skip commit message for ci"

    sub = create_build_context
    assert_not_predicate sub, :skip?
  ensure
    ENV["BUILDKITE_MESSAGE"] = @before_env_buildkite_message
  end

  def test_rails_root
    sub = create_build_context
    assert_equal Pathname.new(Dir.pwd), sub.rails_root
  end

  def test_rails_version
    sub = create_build_context
    sub.stub(:rails_version_file, "6.1.0.rc1") do
      assert_equal sub.rails_version, Gem::Version.new("6.1.0.rc1")
    end
  end

  def test_supports_trilogy
    sub = create_build_context
    sub.stub(:rails_version_file, "6.1.0.rc1") do
      assert_not_predicate sub, :supports_trilogy?
    end

    sub = create_build_context
    sub.stub(:rails_version_file, "7.1.0") do
      assert_predicate sub, :supports_trilogy?
    end
  end

  def test_default_ruby_can_be_set
    build_context = create_build_context

    build_context.default_ruby = Buildkite::Config::RubyConfig.master_ruby

    assert_equal Buildkite::Config::RubyConfig.master_ruby, build_context.default_ruby
  end

  def test_default_ruby
    sub = create_build_context
    rubies = [
      Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.3"), soft_fail: true),
      Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2")),
      Buildkite::Config::RubyConfig.new(version: Gem::Version.new("2.7"))
    ]

    sub.stub(:rubies, rubies) do
      assert_equal sub.default_ruby, rubies[1]
    end
  end

  def test_setup_rubies
    sub = create_build_context

    sub.stub(:min_ruby, Gem::Version.new("2.7")) do
      sub.stub(:max_ruby, Gem::Version.new("3.2")) do
        sub.setup_rubies %w(3.3 3.2 3.1 3.0)
      end
    end

    expected = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: "3.3")

    assert_equal expected.version, sub.rubies.first.version
    assert_equal expected.prefix, sub.rubies.first.prefix
    assert_equal "3.2", sub.default_ruby.version
  end

  def test_setup_preview_rubies
    sub = create_build_context

    sub.stub(:min_ruby, Gem::Version.new("2.7")) do
      sub.stub(:max_ruby, Gem::Version.new("3.5")) do
        sub.setup_rubies %w(3.4.0-rc1 3.3 3.2 3.1 3.0)
      end
    end

    assert_equal "3.4.0-rc1", sub.default_ruby.version.to_s
  end

  def test_setup_rubies_default_ruby
    sub = create_build_context

    sub.stub(:min_ruby, Gem::Version.new("2.7")) do
      sub.stub(:max_ruby, Gem::Version.new("3.2")) do
        sub.setup_rubies %w(3.3 3.2 3.1)
      end
    end

    expected = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: "3.3")

    assert_equal expected.version, sub.rubies.first.version
    assert_equal expected.prefix, sub.rubies.first.prefix
    assert_equal "3.2", sub.default_ruby.version
  end

  def test_bundler_2_2
    sub = create_build_context
    sub.stub(:rails_version, Gem::Version.new("5.1.4")) do
      assert_equal("< 2.2.10", sub.bundler)
    end
  end

  def test_rubygems_3_2
    sub = create_build_context
    sub.stub(:rails_version, Gem::Version.new("5.1.4")) do
      assert_equal("3.2.9", sub.rubygems)
    end
  end

  def test_max_ruby_2_7
    sub = create_build_context
    sub.stub(:rails_version, Gem::Version.new("6.0")) do
      assert_equal sub.max_ruby, Gem::Version.new("2.7")
    end
  end

  def test_remote_image_base
    sub = create_build_context
    assert_equal "973266071021.dkr.ecr.us-east-1.amazonaws.com/builds", sub.send(:remote_image_base)
  end

  def test_registry_default
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV.delete("BUILDKITE_COMPUTE_TYPE")
    @before_env_registry = ENV["REGISTRY"]
    ENV.delete("REGISTRY")

    sub = create_build_context
    assert_equal "973266071021.dkr.ecr.us-east-1.amazonaws.com", sub.send(:registry)
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
    ENV["REGISTRY"] = @before_env_registry
  end

  def test_registry_hosted
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV["BUILDKITE_COMPUTE_TYPE"] = "hosted"
    @before_env_registry = ENV["REGISTRY"]
    ENV["REGISTRY"] = "test_registry_hosted"

    sub = create_build_context
    assert_equal "test_registry_hosted", sub.send(:registry)
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
    ENV["REGISTRY"] = @before_env_registry
  end

  def test_registry_self_hosted
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV["BUILDKITE_COMPUTE_TYPE"] = "self-hosted"
    @before_env_registry = ENV["REGISTRY"]
    ENV["REGISTRY"] = "test_registry_self_hosted"

    sub = create_build_context
    assert_equal "973266071021.dkr.ecr.us-east-1.amazonaws.com", sub.send(:registry)
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
    ENV["REGISTRY"] = @before_env_registry
  end

  def test_registry_env
    @before_env_compute_type = ENV["BUILDKITE_COMPUTE_TYPE"]
    ENV.delete("BUILDKITE_COMPUTE_TYPE")
    @before_env_registry = ENV["REGISTRY"]
    ENV["REGISTRY"] = "test_registry_env"

    sub = create_build_context
    assert_equal "973266071021.dkr.ecr.us-east-1.amazonaws.com", sub.send(:registry)
  ensure
    ENV["BUILDKITE_COMPUTE_TYPE"] = @before_env_compute_type
    ENV["REGISTRY"] = @before_env_registry
  end

  def test_remote_image_base_standard_queues
    sub = create_build_context

    sub.stub(:build_queue, "test_remote_image_base_standard_queues") do
      assert_equal "973266071021.dkr.ecr.us-east-1.amazonaws.com/test_remote_image_base_standard_queues-builds", sub.send(:remote_image_base)
    end
  end

  def test_image_base
    sub = create_build_context
    assert_equal "buildkite-config-base", sub.image_base
  end

  def test_image_base_without_env_docker_image
    @before_docker_image = ENV["DOCKER_IMAGE"]
    ENV["DOCKER_IMAGE"] = nil

    sub = create_build_context
    assert_equal sub.send(:remote_image_base), sub.image_base
  ensure
    ENV["DOCKER_IMAGE"] = @before_docker_image
  end

  def test_image_name_for
    sub = create_build_context
    sub.ruby = Buildkite::Config::RubyConfig.new(prefix: "ruby:", version: Gem::Version.new("3.3"))
    assert_equal "base:buildkite-config-base:ruby-3-3-br-main", sub.image_name_for("br-main")
  end

  def test_build_id
    sub = create_build_context
    assert_equal "local", sub.build_id
  end

  def test_build_id_without_env_buildkite_build_id_and_with_env_build_id
    @before_build_id = ENV["BUILD_ID"]
    @before_buildkite_build_id = ENV["BUILDKITE_BUILD_ID"]
    ENV["BUILD_ID"] = "test_build_id_without_env_buildkite_build_id_and_with_env_build_id"
    ENV["BUILDKITE_BUILD_ID"] = nil

    sub = create_build_context
    assert_equal "test_build_id_without_env_buildkite_build_id_and_with_env_build_id", sub.build_id
  ensure
    ENV["BUILD_ID"] = @before_build_id
    ENV["BUILDKITE_BUILD_ID"] = @before_buildkite_build_id
  end

  def test_build_id_without_env
    @before_build_id = ENV["BUILD_ID"]
    @before_buildkite_build_id = ENV["BUILDKITE_BUILD_ID"]
    ENV["BUILD_ID"] = nil
    ENV["BUILDKITE_BUILD_ID"] = nil

    sub = create_build_context
    assert_equal "build_id", sub.build_id
  ensure
    ENV["BUILD_ID"] = @before_build_id
    ENV["BUILDKITE_BUILD_ID"] = @before_buildkite_build_id
  end

  def test_rebuild_id
    @before_buildkite_rebuilt_from_build_id = ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]
    ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"] = nil

    sub = create_build_context
    assert_nil sub.rebuild_id
  ensure
    ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"] = @before_buildkite_rebuilt_from_build_id
  end

  def test_rebuild_id_blank
    @before_buildkite_rebuilt_from_build_id = ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]
    ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"] = ""

    sub = create_build_context
    assert_nil sub.rebuild_id
  ensure
    ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"] = @before_buildkite_rebuilt_from_build_id
  end

  def test_rebuild_id_with_env
    @before_buildkite_rebuilt_from_build_id = ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"]
    ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"] = "test_rebuild_id_with_env"

    sub = create_build_context
    assert_equal "test_rebuild_id_with_env", sub.rebuild_id
  ensure
    ENV["BUILDKITE_REBUILT_FROM_BUILD_ID"] = @before_buildkite_rebuilt_from_build_id
  end

  def test_base_branch_blank
    @before_buildkite_pull_request_base_branch = ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"]
    @before_buildkite_branch = ENV["BUILDKITE_BRANCH"]
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = ""
    ENV["BUILDKITE_BRANCH"] = ""

    sub = create_build_context
    assert_equal "main", sub.base_branch
  ensure
    ENV["BUILDKITE_BRANCH"] = @before_buildkite_branch
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = @before_buildkite_pull_request_base_branch
  end

  def test_base_branch_nil
    @before_buildkite_pull_request_base_branch = ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"]
    @before_buildkite_branch = ENV["BUILDKITE_BRANCH"]
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = nil
    ENV["BUILDKITE_BRANCH"] = nil

    sub = create_build_context
    assert_nil sub.base_branch
  ensure
    ENV["BUILDKITE_BRANCH"] = @before_buildkite_branch
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = @before_buildkite_pull_request_base_branch
  end

  def test_base_branch_with_env_buildkite_pull_request_base_branch
    @before_buildkite_pull_request_base_branch = ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"]
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = "test_base_branch_with_env_buildkite_pull_request_base_branch"

    sub = create_build_context
    assert_equal "test_base_branch_with_env_buildkite_pull_request_base_branch", sub.base_branch
  ensure
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = @before_buildkite_pull_request_base_branch
  end

  def test_base_branch_with_env_buildkite_branch
    @before_buildkite_pull_request_base_branch = ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"]
    @before_buildkite_branch = ENV["BUILDKITE_BRANCH"]
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = ""
    ENV["BUILDKITE_BRANCH"] = "test_base_branch_with_env_buildkite_branch"

    sub = create_build_context
    assert_equal "test_base_branch_with_env_buildkite_branch", sub.base_branch
  ensure
    ENV["BUILDKITE_BRANCH"] = @before_buildkite_branch
    ENV["BUILDKITE_PULL_REQUEST_BASE_BRANCH"] = @before_buildkite_pull_request_base_branch
  end

  def test_local_branch
    @before_buildkite_branch = ENV["BUILDKITE_BRANCH"]
    ENV["BUILDKITE_BRANCH"] = "test_local_branch"

    sub = create_build_context
    assert_equal "test_local_branch", sub.local_branch
  ensure
    ENV["BUILDKITE_BRANCH"] = @before_buildkite_branch
  end

  def test_local_branch_blank
    @before_buildkite_branch = ENV["BUILDKITE_BRANCH"]
    ENV["BUILDKITE_BRANCH"] = ""

    sub = create_build_context
    assert_equal "main", sub.local_branch
  ensure
    ENV["BUILDKITE_BRANCH"] = @before_buildkite_branch
  end

  def test_local_branch_nil
    @before_buildkite_branch = ENV["BUILDKITE_BRANCH"]
    ENV["BUILDKITE_BRANCH"] = nil

    sub = create_build_context
    assert_nil sub.local_branch
  ensure
    ENV["BUILDKITE_BRANCH"] = @before_buildkite_branch
  end

  def test_mainline
    sub = create_build_context
    sub.stub(:local_branch, "main") do
      assert sub.mainline
    end
  end

  def test_mainline_stable
    sub = create_build_context
    sub.stub(:local_branch, "7-0-stable") do
      assert sub.mainline
    end
  end

  def test_mainline_non_stable_branch
    sub = create_build_context
    sub.stub(:local_branch, "bump/trilogy") do
      assert_not sub.mainline
    end
  end

  def test_pull_request
    @before_buildkite_pull_request = ENV["BUILDKITE_PULL_REQUEST"]
    ENV["BUILDKITE_PULL_REQUEST"] = "42"

    sub = create_build_context
    assert_equal "42", sub.pull_request
  ensure
    ENV["BUILDKITE_PULL_REQUEST"] = @before_buildkite_pull_request
  end

  def test_not_a_pull_request
    @before_buildkite_pull_request = ENV["BUILDKITE_PULL_REQUEST"]
    ENV["BUILDKITE_PULL_REQUEST"] = "false"

    sub = create_build_context
    assert_nil sub.pull_request
  ensure
    ENV["BUILDKITE_PULL_REQUEST"] = @before_buildkite_pull_request
  end

  def test_not_a_pull_request_nil
    @before_buildkite_pull_request = ENV["BUILDKITE_PULL_REQUEST"]
    ENV["BUILDKITE_PULL_REQUEST"] = nil

    sub = create_build_context
    assert_nil sub.pull_request
  ensure
    ENV["BUILDKITE_PULL_REQUEST"] = @before_buildkite_pull_request
  end

  def test_queue
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = "test_queue"

    sub = create_build_context
    assert_equal "test_queue", sub.queue
  ensure
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_queue_with_standard_queues_default
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = "default"

    sub = create_build_context
    assert_nil sub.queue
  ensure
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_queue_with_standard_queues_builder
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = "builder"

    sub = create_build_context
    assert_nil sub.queue
  ensure
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_queue_with_standard_queues_nil
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = nil

    sub = create_build_context
    assert_nil sub.queue
  ensure
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_build_queue_with_env
    @before_build_queue = ENV["BUILD_QUEUE"]
    ENV["BUILD_QUEUE"] = "test_build_queue_with_env"

    sub = create_build_context
    assert_equal "test_build_queue_with_env", sub.build_queue
  ensure
    ENV["BUILD_QUEUE"] = @before_build_queue
  end

  def test_build_queue_with_meta_data_queue
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = "test_build_queue_with_meta_data_queue"

    sub = create_build_context
    assert_equal "test_build_queue_with_meta_data_queue", sub.build_queue
  ensure
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_build_queue_with_no_env
    @before_build_queue = ENV["BUILD_QUEUE"]
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["BUILD_QUEUE"] = nil
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = nil

    sub = create_build_context
    assert_equal "builder", sub.build_queue
  ensure
    ENV["BUILD_QUEUE"] = @before_build_queue
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_run_queue_with_env
    @before_run_queue = ENV["RUN_QUEUE"]
    ENV["RUN_QUEUE"] = "test_run_queue_with_env"

    sub = create_build_context
    assert_equal "test_run_queue_with_env", sub.run_queue
  ensure
    ENV["RUN_QUEUE"] = @before_run_queue
  end

  def test_run_queue_with_meta_data_queue
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = "test_run_queue_with_meta_data_queue"

    sub = create_build_context
    assert_equal "test_run_queue_with_meta_data_queue", sub.run_queue
  ensure
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_run_queue_with_no_env
    @before_run_queue = ENV["RUN_QUEUE"]
    @before_buildkite_agent_meta_data_queue = ENV["BUILDKITE_AGENT_META_DATA_QUEUE"]
    ENV["RUN_QUEUE"] = nil
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = nil

    sub = create_build_context
    assert_equal "default", sub.run_queue
  ensure
    ENV["RUN_QUEUE"] = @before_run_queue
    ENV["BUILDKITE_AGENT_META_DATA_QUEUE"] = @before_buildkite_agent_meta_data_queue
  end

  def test_artifact_paths
    sub = create_build_context
    assert_equal ["test-reports/*/*.xml"], sub.artifact_paths
  end

  def test_automatic_retry_on
    sub = create_build_context
    assert_equal([{ exit_status: -1, limit: 2 }, { exit_status: 255, limit: 2 }], sub.automatic_retry_on)
  end

  def test_timeout_in_minutes
    sub = create_build_context
    assert_equal 30, sub.timeout_in_minutes
  end

  def test_has_railspect
    sub = create_build_context
    assert_not_predicate sub, :has_railspect?

    file_check = -> (path) do
      assert_equal "#{Dir.pwd}/tools/railspect", path.to_s
    end

    File.stub(:exist?, file_check) do
      assert_predicate sub, :has_railspect?
    end
  end

  def test_support_guides_lint
    sub = create_build_context

    sub.stub(:rails_version, Gem::Version.new("7.0.0")) do
      assert_not_predicate sub, :support_guides_lint?
    end

    sub.stub(:rails_version, Gem::Version.new("7.1.0")) do
      assert_predicate sub, :support_guides_lint?
    end
  end

  def test_test_with_multiple_versions_of_rack
    sub = create_build_context

    sub.default_ruby = Buildkite::Config::RubyConfig.master_ruby

    sub.stub(:rails_version, Gem::Version.new("7.0.0")) do
      assert_equal false, sub.test_with_multiple_versions_of_rack?(Buildkite::Config::RubyConfig.master_ruby)
    end

    sub.stub(:rails_version, Gem::Version.new("7.2.0")) do
      assert_equal false, sub.test_with_multiple_versions_of_rack?(Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2")))
    end

    sub.stub(:rails_version, Gem::Version.new("7.2.0")) do
      assert_equal true, sub.test_with_multiple_versions_of_rack?(Buildkite::Config::RubyConfig.master_ruby)
    end

    Buildkite::Config::RubyConfig.new(version: Gem::Version.new("3.2"))
  end
end
