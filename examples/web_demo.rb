#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing the Sidekiq Assured Jobs web interface
# Run this script and visit http://localhost:4567/orphaned-jobs

require 'bundler/setup'
require 'sidekiq'
require 'sidekiq/web'
require_relative '../lib/sidekiq-assured-jobs'

# Configure Redis for demo
Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://localhost:6379/15' } # Use test database
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379/15' } # Use test database
end

# Configure AssuredJobs for demo
Sidekiq::AssuredJobs.configure do |config|
  config.namespace = "demo_assured_jobs"
  config.heartbeat_interval = 5
  config.heartbeat_ttl = 15
  config.auto_recovery_enabled = false # Disable auto-recovery for demo
end

# Demo worker class
class DemoWorker
  include Sidekiq::Worker
  include Sidekiq::AssuredJobs::Worker

  def perform(message, delay = 0)
    puts "Processing: #{message}"
    sleep(delay) if delay > 0
    puts "Completed: #{message}"
  end
end

# Create some demo orphaned jobs
def create_demo_orphaned_jobs
  puts "Creating demo orphaned jobs..."
  
  # Simulate orphaned jobs by creating tracking data without live instances
  dead_instances = ["demo-worker-1", "demo-worker-2", "demo-worker-3"]
  
  Sidekiq::AssuredJobs.redis_sync do |conn|
    dead_instances.each_with_index do |instance_id, i|
      # Create some orphaned jobs for each dead instance
      (1..3).each do |job_num|
        jid = "demo_job_#{instance_id}_#{job_num}"
        job_data = {
          "class" => "DemoWorker",
          "args" => ["Demo job #{job_num} from #{instance_id}", 2],
          "jid" => jid,
          "queue" => "default",
          "created_at" => (Time.now - (i * 300) - (job_num * 60)).to_f,
          "enqueued_at" => (Time.now - (i * 300) - (job_num * 60)).to_f,
          "retry_count" => job_num - 1
        }
        
        # Add to tracking
        job_tracking_key = Sidekiq::AssuredJobs.send(:namespaced_key, "jobs:#{instance_id}")
        job_data_key = Sidekiq::AssuredJobs.send(:namespaced_key, "job:#{jid}")
        
        conn.sadd(job_tracking_key, jid)
        conn.set(job_data_key, job_data.to_json)
      end
    end
  end
  
  puts "Created #{dead_instances.size * 3} demo orphaned jobs"
end

# Create some live instances for comparison
def create_demo_live_instances
  puts "Creating demo live instances..."
  
  live_instances = ["live-worker-1", "live-worker-2"]
  
  Sidekiq::AssuredJobs.redis_sync do |conn|
    live_instances.each do |instance_id|
      key = Sidekiq::AssuredJobs.send(:namespaced_key, "instance:#{instance_id}")
      conn.setex(key, 60, Time.now.to_f)
    end
  end
  
  puts "Created #{live_instances.size} demo live instances"
end

# Clean up demo data
def cleanup_demo_data
  puts "Cleaning up demo data..."
  
  Sidekiq::AssuredJobs.redis_sync do |conn|
    keys = conn.keys("#{Sidekiq::AssuredJobs.namespace}:*")
    conn.del(*keys) if keys.any?
  end
  
  puts "Demo data cleaned up"
end

# Setup demo data
puts "Setting up demo environment..."
cleanup_demo_data
create_demo_orphaned_jobs
create_demo_live_instances

puts "\n" + "="*60
puts "SIDEKIQ ASSURED JOBS WEB DEMO"
puts "="*60
puts ""
puts "Demo server starting at: http://localhost:4567"
puts ""
puts "Available endpoints:"
puts "  • Main dashboard:     http://localhost:4567/"
puts "  • Orphaned Jobs:      http://localhost:4567/orphaned-jobs"
puts "  • Job stats (JSON):   http://localhost:4567/orphaned-jobs/stats"
puts ""
puts "Demo features:"
puts "  • View orphaned jobs from 3 'dead' worker instances"
puts "  • See live vs dead instance status"
puts "  • Try retrying or deleting orphaned jobs"
puts "  • Test bulk operations"
puts "  • View detailed job information"
puts ""
puts "Press Ctrl+C to stop the demo and clean up"
puts "="*60
puts ""

# Trap interrupt to cleanup
trap('INT') do
  puts "\n\nShutting down demo..."
  cleanup_demo_data
  puts "Demo data cleaned up. Goodbye!"
  exit
end

# Start the web server
require 'rack'

app = Rack::Builder.new do
  use Rack::ShowExceptions
  run Sidekiq::Web
end

Rack::Handler::WEBrick.run(app, Port: 4567, Host: '0.0.0.0') do |server|
  puts "Demo server started successfully!"
  puts "Visit http://localhost:4567/orphaned-jobs to see the dashboard"
end
