# frozen_string_literal: true

require_relative "../lib/sidekiq-processing-tracker"
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
      Sidekiq::ProcessingTracker.redis_sync { |conn| conn.flushdb }
    rescue Redis::CannotConnectError
      # Skip if Redis is not available
    end

    # Reset configuration to defaults
    Sidekiq::ProcessingTracker.instance_variable_set(:@instance_id, nil)
    Sidekiq::ProcessingTracker.instance_variable_set(:@namespace, nil)
    Sidekiq::ProcessingTracker.instance_variable_set(:@heartbeat_interval, nil)
    Sidekiq::ProcessingTracker.instance_variable_set(:@heartbeat_ttl, nil)
    Sidekiq::ProcessingTracker.instance_variable_set(:@recovery_lock_ttl, nil)

    # Reconfigure with test settings
    Sidekiq::ProcessingTracker.configure do |config|
      config.heartbeat_interval = 1 # Fast heartbeat for tests
      config.heartbeat_ttl = 3
      config.recovery_lock_ttl = 10
    end
  end

  config.after(:each) do
    # Clean up Redis after each test
    Sidekiq::ProcessingTracker.redis_sync { |conn| conn.flushdb }
  end
end

# Test worker classes
class TestWorker
  include Sidekiq::Worker
  include Sidekiq::ProcessingTracker::Worker

  def perform(arg = nil)
    # Simple test job
    sleep 0.1 if arg == "slow"
  end
end

class NonTrackedWorker
  include Sidekiq::Worker

  def perform
    # This worker doesn't include ProcessingTracker::Worker
  end
end
