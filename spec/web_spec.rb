# frozen_string_literal: true

require "spec_helper"

# Only run web tests if Sidekiq::Web is available
begin
  require "sidekiq/web"
  require "rack/test"
  
  RSpec.describe Sidekiq::AssuredJobs::Web do
    include Rack::Test::Methods

    let(:namespace) { Sidekiq::AssuredJobs.namespace }
    let(:instance_id) { Sidekiq::AssuredJobs.instance_id }

    def app
      Sidekiq::Web
    end

    def redis_sync(&block)
      Sidekiq::AssuredJobs.redis_sync(&block)
    end

    before do
      # Clear Redis before each test
      redis_sync { |conn| conn.flushdb }
    end

    describe "GET /orphaned-jobs" do
      context "when there are no orphaned jobs" do
        it "shows empty state" do
          get "/orphaned-jobs"
          
          expect(last_response).to be_ok
          expect(last_response.body).to include("No Orphaned Jobs!")
        end
      end

      context "when there are orphaned jobs" do
        let(:job_data) do
          {
            "class" => "TestWorker",
            "args" => ["test_arg"],
            "jid" => "test_jid_123",
            "queue" => "default",
            "created_at" => Time.now.to_f,
            "enqueued_at" => Time.now.to_f
          }
        end

        before do
          # Create orphaned job
          redis_sync do |conn|
            dead_instance = "dead_instance_123"
            conn.sadd("#{namespace}:jobs:#{dead_instance}", job_data["jid"])
            conn.set("#{namespace}:job:#{job_data['jid']}", job_data.to_json)
          end
        end

        it "displays orphaned jobs" do
          get "/orphaned-jobs"
          
          expect(last_response).to be_ok
          expect(last_response.body).to include("TestWorker")
          expect(last_response.body).to include("test_jid_123")
          expect(last_response.body).to include("default")
        end

        it "shows instance status" do
          get "/orphaned-jobs"
          
          expect(last_response).to be_ok
          expect(last_response.body).to include("Instance Status")
          expect(last_response.body).to include("DEAD")
        end
      end
    end

    describe "GET /orphaned-jobs/:jid" do
      let(:job_data) do
        {
          "class" => "TestWorker",
          "args" => ["test_arg"],
          "jid" => "test_jid_123",
          "queue" => "default",
          "created_at" => Time.now.to_f,
          "enqueued_at" => Time.now.to_f
        }
      end

      before do
        # Create orphaned job
        redis_sync do |conn|
          dead_instance = "dead_instance_123"
          conn.sadd("#{namespace}:jobs:#{dead_instance}", job_data["jid"])
          conn.set("#{namespace}:job:#{job_data['jid']}", job_data.to_json)
        end
      end

      it "shows job details" do
        get "/orphaned-jobs/test_jid_123"
        
        expect(last_response).to be_ok
        expect(last_response.body).to include("Orphaned Job Details")
        expect(last_response.body).to include("TestWorker")
        expect(last_response.body).to include("test_jid_123")
        expect(last_response.body).to include("test_arg")
      end

      it "returns 404 for non-existent job" do
        get "/orphaned-jobs/non_existent_jid"
        
        expect(last_response.status).to eq(404)
      end
    end

    describe "POST /orphaned-jobs/:jid/retry" do
      let(:job_data) do
        {
          "class" => "TestWorker",
          "args" => ["test_arg"],
          "jid" => "test_jid_123",
          "queue" => "default"
        }
      end

      before do
        # Create orphaned job
        redis_sync do |conn|
          dead_instance = "dead_instance_123"
          conn.sadd("#{namespace}:jobs:#{dead_instance}", job_data["jid"])
          conn.set("#{namespace}:job:#{job_data['jid']}", job_data.to_json)
        end
      end

      it "retries the orphaned job" do
        expect(Sidekiq::Client).to receive(:push).with(job_data)
        
        post "/orphaned-jobs/test_jid_123/retry"
        
        expect(last_response.status).to eq(302) # Redirect
        expect(last_response.location).to include("/orphaned-jobs")
        
        # Job should be cleaned up
        redis_sync do |conn|
          expect(conn.exists("#{namespace}:job:test_jid_123")).to eq(0)
        end
      end

      it "returns error for non-existent job" do
        post "/orphaned-jobs/non_existent_jid/retry"
        
        expect(last_response.status).to eq(400)
      end
    end

    describe "POST /orphaned-jobs/:jid/delete" do
      let(:job_data) do
        {
          "class" => "TestWorker",
          "args" => ["test_arg"],
          "jid" => "test_jid_123",
          "queue" => "default"
        }
      end

      before do
        # Create orphaned job
        redis_sync do |conn|
          dead_instance = "dead_instance_123"
          conn.sadd("#{namespace}:jobs:#{dead_instance}", job_data["jid"])
          conn.set("#{namespace}:job:#{job_data['jid']}", job_data.to_json)
        end
      end

      it "deletes the orphaned job" do
        post "/orphaned-jobs/test_jid_123/delete"
        
        expect(last_response.status).to eq(302) # Redirect
        expect(last_response.location).to include("/orphaned-jobs")
        
        # Job should be cleaned up
        redis_sync do |conn|
          expect(conn.exists("#{namespace}:job:test_jid_123")).to eq(0)
        end
      end

      it "returns error for non-existent job" do
        post "/orphaned-jobs/non_existent_jid/delete"
        
        expect(last_response.status).to eq(400)
      end
    end

    describe "POST /orphaned-jobs/bulk-action" do
      let(:job_data_1) do
        {
          "class" => "TestWorker",
          "args" => ["test_arg_1"],
          "jid" => "test_jid_1",
          "queue" => "default"
        }
      end

      let(:job_data_2) do
        {
          "class" => "TestWorker",
          "args" => ["test_arg_2"],
          "jid" => "test_jid_2",
          "queue" => "default"
        }
      end

      before do
        # Create orphaned jobs
        redis_sync do |conn|
          dead_instance = "dead_instance_123"
          conn.sadd("#{namespace}:jobs:#{dead_instance}", job_data_1["jid"])
          conn.sadd("#{namespace}:jobs:#{dead_instance}", job_data_2["jid"])
          conn.set("#{namespace}:job:#{job_data_1['jid']}", job_data_1.to_json)
          conn.set("#{namespace}:job:#{job_data_2['jid']}", job_data_2.to_json)
        end
      end

      it "retries multiple jobs" do
        expect(Sidekiq::Client).to receive(:push).with(job_data_1)
        expect(Sidekiq::Client).to receive(:push).with(job_data_2)
        
        post "/orphaned-jobs/bulk-action", {
          action: "retry",
          jids: ["test_jid_1", "test_jid_2"]
        }
        
        expect(last_response.status).to eq(302) # Redirect
      end

      it "deletes multiple jobs" do
        post "/orphaned-jobs/bulk-action", {
          action: "delete",
          jids: ["test_jid_1", "test_jid_2"]
        }
        
        expect(last_response.status).to eq(302) # Redirect
        
        # Jobs should be cleaned up
        redis_sync do |conn|
          expect(conn.exists("#{namespace}:job:test_jid_1")).to eq(0)
          expect(conn.exists("#{namespace}:job:test_jid_2")).to eq(0)
        end
      end

      it "returns error for invalid action" do
        post "/orphaned-jobs/bulk-action", {
          action: "invalid",
          jids: ["test_jid_1"]
        }
        
        expect(last_response.status).to eq(400)
      end
    end

    describe "GET /orphaned-jobs/stats" do
      it "returns stats in JSON format" do
        get "/orphaned-jobs/stats"
        
        expect(last_response).to be_ok
        expect(last_response.content_type).to include("application/json")
        
        stats = JSON.parse(last_response.body)
        expect(stats).to have_key("total_orphaned_jobs")
        expect(stats).to have_key("dead_instances")
        expect(stats).to have_key("live_instances")
      end
    end
  end

rescue LoadError
  # Sidekiq::Web not available, skip web tests
  puts "Skipping web tests - Sidekiq::Web not available"
end
