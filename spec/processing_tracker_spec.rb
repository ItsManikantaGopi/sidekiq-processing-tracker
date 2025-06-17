# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::ProcessingTracker do
  let(:namespace) { described_class.namespace }
  let(:instance_id) { described_class.instance_id }

  def redis_sync(&block)
    described_class.redis_sync(&block)
  end

  describe ".configure" do
    it "sets up default configuration" do
      expect(described_class.instance_id).to be_a(String)
      expect(described_class.namespace).to eq("sidekiq_processing")
      expect(described_class.heartbeat_interval).to eq(1) # Set in spec_helper
      expect(described_class.heartbeat_ttl).to eq(3)
      expect(described_class.recovery_lock_ttl).to eq(10)
    end

    it "respects environment variables" do
      # Reset configuration first
      described_class.instance_variable_set(:@namespace, nil)
      described_class.instance_variable_set(:@heartbeat_interval, nil)

      ENV["PROCESSING_NS"] = "test_namespace"
      ENV["HEARTBEAT_INTERVAL"] = "5"

      described_class.configure

      expect(described_class.namespace).to eq("test_namespace")
      expect(described_class.heartbeat_interval).to eq(5)

      # Clean up
      ENV.delete("PROCESSING_NS")
      ENV.delete("HEARTBEAT_INTERVAL")
    end
  end

  describe "heartbeat system" do
    it "creates heartbeat keys in Redis" do
      sleep 0.1 # Give heartbeat thread a moment

      heartbeat_key = "#{namespace}:instance:#{instance_id}"
      redis_sync do |conn|
        expect(conn.exists(heartbeat_key)).to eq(1)

        # Check that the value is a timestamp
        timestamp = conn.get(heartbeat_key).to_f
        expect(timestamp).to be > (Time.now.to_f - 10)
      end
    end

    it "refreshes heartbeat periodically" do
      heartbeat_key = "#{namespace}:instance:#{instance_id}"

      # Get initial timestamp
      sleep 0.1
      initial_timestamp = redis_sync { |conn| conn.get(heartbeat_key).to_f }

      # Wait for refresh
      sleep 1.5
      new_timestamp = redis_sync { |conn| conn.get(heartbeat_key).to_f }

      expect(new_timestamp).to be > initial_timestamp
    end
  end

  describe ".reenqueue_orphans!" do
    let(:other_instance_id) { "dead_instance_123" }
    let(:job_data) do
      {
        "class" => "TestWorker",
        "args" => ["test_arg"],
        "jid" => "test_jid_123",
        "queue" => "default"
      }
    end

    before do
      # Simulate a dead instance with orphaned jobs
      redis_sync do |conn|
        conn.sadd("#{namespace}:jobs:#{other_instance_id}", job_data["jid"])
        conn.set("#{namespace}:job:#{job_data['jid']}", job_data.to_json)
      end
    end

    it "re-enqueues jobs from dead instances" do
      expect(Sidekiq::Client).to receive(:push).with(job_data)

      described_class.reenqueue_orphans!

      # Check that tracking keys are cleaned up
      redis_sync do |conn|
        expect(conn.exists("#{namespace}:jobs:#{other_instance_id}")).to eq(0)
        expect(conn.exists("#{namespace}:job:#{job_data['jid']}")).to eq(0)
      end
    end

    it "doesn't re-enqueue jobs from live instances" do
      # Create a heartbeat for the "dead" instance to make it live
      redis_sync { |conn| conn.setex("#{namespace}:instance:#{other_instance_id}", 60, Time.now.to_f) }

      expect(Sidekiq::Client).not_to receive(:push)

      described_class.reenqueue_orphans!

      # Job should still be tracked since instance is alive
      redis_sync { |conn| expect(conn.exists("#{namespace}:jobs:#{other_instance_id}")).to eq(1) }
    end

    it "uses distributed locking to prevent concurrent recovery" do
      # Simulate another instance holding the lock
      lock_key = "#{namespace}:recovery_lock"
      redis_sync { |conn| conn.set(lock_key, "other_instance", nx: true, ex: 300) }

      expect(Sidekiq::Client).not_to receive(:push)

      described_class.reenqueue_orphans!

      # Job should still be there since recovery was skipped
      redis_sync { |conn| expect(conn.exists("#{namespace}:jobs:#{other_instance_id}")).to eq(1) }
    end

    it "only runs recovery once when called multiple times concurrently" do
      call_count = 0
      allow(Sidekiq::Client).to receive(:push) do |job|
        call_count += 1
        expect(job).to eq(job_data)
      end

      # Run recovery multiple times concurrently
      threads = 3.times.map do
        Thread.new { described_class.reenqueue_orphans! }
      end
      threads.each(&:join)

      # Should only push the job once
      expect(call_count).to eq(1)
    end
  end

  describe ".with_recovery_lock" do
    it "executes block when lock is acquired" do
      executed = false
      
      described_class.send(:with_recovery_lock) do
        executed = true
      end
      
      expect(executed).to be true
    end

    it "skips block when lock is held by another instance" do
      lock_key = "#{namespace}:recovery_lock"
      redis_sync { |conn| conn.set(lock_key, "other_instance", nx: true, ex: 300) }

      executed = false

      described_class.send(:with_recovery_lock) do
        executed = true
      end

      expect(executed).to be false
    end

    it "releases lock after execution" do
      lock_key = "#{namespace}:recovery_lock"
      lock_value_during_execution = nil

      described_class.send(:with_recovery_lock) do
        redis_sync { |conn| lock_value_during_execution = conn.get(lock_key) }
      end

      # Check that lock was held during execution
      expect(lock_value_during_execution).to eq(instance_id)

      # Check that lock is released after execution
      redis_sync { |conn| expect(conn.exists(lock_key)).to eq(0) }
    end

    it "releases lock even if block raises an error" do
      lock_key = "#{namespace}:recovery_lock"

      expect do
        described_class.send(:with_recovery_lock) do
          raise "test error"
        end
      end.to raise_error("test error")

      redis_sync { |conn| expect(conn.exists(lock_key)).to eq(0) }
    end
  end
end
