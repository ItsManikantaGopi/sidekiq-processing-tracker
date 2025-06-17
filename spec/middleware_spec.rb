# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sidekiq::ProcessingTracker::Middleware do
  let(:middleware) { described_class.new }
  let(:namespace) { Sidekiq::ProcessingTracker.namespace }
  let(:instance_id) { Sidekiq::ProcessingTracker.instance_id }

  def redis_sync(&block)
    Sidekiq::ProcessingTracker.redis_sync(&block)
  end
  
  let(:job_data) do
    {
      "class" => "TestWorker",
      "args" => ["test_arg"],
      "jid" => "test_jid_123",
      "queue" => "default"
    }
  end

  describe "#call" do
    context "with a tracked worker" do
      let(:worker) { TestWorker.new }

      it "adds job to tracking before execution" do
        job_tracking_key = "#{namespace}:jobs:#{instance_id}"
        job_data_key = "#{namespace}:job:#{job_data['jid']}"

        middleware.call(worker, job_data, "default") do
          # During execution, job should be tracked
          redis_sync do |conn|
            expect(conn.sismember(job_tracking_key, job_data["jid"])).to be true
            expect(conn.exists(job_data_key)).to eq(1)

            stored_job = JSON.parse(conn.get(job_data_key))
            expect(stored_job).to eq(job_data)
          end
        end
      end

      it "removes job from tracking after execution" do
        job_tracking_key = "#{namespace}:jobs:#{instance_id}"
        job_data_key = "#{namespace}:job:#{job_data['jid']}"

        middleware.call(worker, job_data, "default") do
          # Job execution
        end

        # After execution, job should not be tracked
        redis_sync do |conn|
          expect(conn.sismember(job_tracking_key, job_data["jid"])).to be false
          expect(conn.exists(job_data_key)).to eq(0)
        end
      end

      it "removes job from tracking even if job raises an error" do
        job_tracking_key = "#{namespace}:jobs:#{instance_id}"
        job_data_key = "#{namespace}:job:#{job_data['jid']}"

        expect do
          middleware.call(worker, job_data, "default") do
            raise "job error"
          end
        end.to raise_error("job error")

        # Job should still be cleaned up
        redis_sync do |conn|
          expect(conn.sismember(job_tracking_key, job_data["jid"])).to be false
          expect(conn.exists(job_data_key)).to eq(0)
        end
      end

      it "handles multiple concurrent jobs" do
        job_data_2 = job_data.merge("jid" => "test_jid_456")
        job_tracking_key = "#{namespace}:jobs:#{instance_id}"
        
        # Start first job
        thread1 = Thread.new do
          middleware.call(worker, job_data, "default") do
            sleep 0.2 # Simulate work
          end
        end
        
        sleep 0.05 # Let first job start
        
        # Start second job
        thread2 = Thread.new do
          middleware.call(worker, job_data_2, "default") do
            sleep 0.1 # Simulate work
          end
        end
        
        sleep 0.05 # Let second job start
        
        # Both jobs should be tracked
        redis_sync do |conn|
          expect(conn.sismember(job_tracking_key, job_data["jid"])).to be true
          expect(conn.sismember(job_tracking_key, job_data_2["jid"])).to be true
        end

        # Wait for jobs to complete
        thread1.join
        thread2.join

        # No jobs should be tracked after completion
        redis_sync { |conn| expect(conn.scard(job_tracking_key)).to eq(0) }
      end
    end

    context "with a non-tracked worker" do
      let(:worker) { NonTrackedWorker.new }

      it "does not track the job" do
        job_tracking_key = "#{namespace}:jobs:#{instance_id}"
        job_data_key = "#{namespace}:job:#{job_data['jid']}"

        executed = false
        middleware.call(worker, job_data, "default") do
          executed = true
          # Job should not be tracked
          redis_sync do |conn|
            expect(conn.sismember(job_tracking_key, job_data["jid"])).to be false
            expect(conn.exists(job_data_key)).to eq(0)
          end
        end

        expect(executed).to be true

        # Still not tracked after execution
        redis_sync do |conn|
          expect(conn.sismember(job_tracking_key, job_data["jid"])).to be false
          expect(conn.exists(job_data_key)).to eq(0)
        end
      end
    end
  end

  describe "#should_track_job?" do
    it "returns true for workers with processing: true option" do
      worker = TestWorker.new
      expect(middleware.send(:should_track_job?, worker, job_data)).to be true
    end

    it "returns false for workers without processing option" do
      worker = NonTrackedWorker.new
      expect(middleware.send(:should_track_job?, worker, job_data)).to be false
    end

    it "works with worker classes" do
      expect(middleware.send(:should_track_job?, TestWorker, job_data)).to be true
      expect(middleware.send(:should_track_job?, NonTrackedWorker, job_data)).to be false
    end
  end
end
