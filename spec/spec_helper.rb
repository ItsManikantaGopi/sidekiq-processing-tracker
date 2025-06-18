# frozen_string_literal: true

require_relative "../lib/sidekiq-assured-jobs"
require "rspec"

# Configure test Redis database
ENV["REDIS_URL"] = "redis://localhost:6379/15"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    # Flush Redis before each test
    begin
      Sidekiq::AssuredJobs.redis_sync { |conn| conn.flushdb }
    rescue Redis::CannotConnectError
      # Skip if Redis is not available
    end

    # Reset configuration to defaults
    Sidekiq::AssuredJobs.instance_variable_set(:@instance_id, nil)
    Sidekiq::AssuredJobs.instance_variable_set(:@namespace, nil)
    Sidekiq::AssuredJobs.instance_variable_set(:@heartbeat_interval, nil)
    Sidekiq::AssuredJobs.instance_variable_set(:@heartbeat_ttl, nil)
    Sidekiq::AssuredJobs.instance_variable_set(:@recovery_lock_ttl, nil)

    # Reconfigure with test settings
    Sidekiq::AssuredJobs.configure do |config|
      config.heartbeat_interval = 1 # Fast heartbeat for tests
      config.heartbeat_ttl = 3
      config.recovery_lock_ttl = 10
    end

    # Ensure defaults are set up for tests
    Sidekiq::AssuredJobs.send(:setup_defaults)
  end

  config.after(:each) do
    # Clean up Redis after each test
    Sidekiq::AssuredJobs.redis_sync { |conn| conn.flushdb }
  end
end

# Test worker classes
class TestWorker
  include Sidekiq::Worker
  include Sidekiq::AssuredJobs::Worker

  def perform(arg = nil)
    # Simple test job
    sleep 0.1 if arg == "slow"
  end
end

class NonTrackedWorker
  include Sidekiq::Worker

  def perform
    # This worker doesn't include AssuredJobs::Worker
  end
end
