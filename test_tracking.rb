#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify job tracking is working
require_relative "lib/sidekiq-processing-tracker"

# Your worker class
class IdentityPhotoGenerationWorker
  include Sidekiq::Worker
  include Sidekiq::ProcessingTracker::Worker  # Enables tracking
 
  def perform()
    puts "IdentityPhotoGenerationWorker executed"
    sleep 2  # Simulate some work
    puts "IdentityPhotoGenerationWorker completed"
  end
end

# Test the middleware directly
puts "=== Testing Middleware Directly ==="

middleware = Sidekiq::ProcessingTracker::Middleware.new
worker = IdentityPhotoGenerationWorker.new

# Simulate a job payload
job_data = {
  "class" => "IdentityPhotoGenerationWorker",
  "args" => [],
  "jid" => "test_jid_#{Time.now.to_i}",
  "queue" => "default"
}

puts "Worker sidekiq_options: #{IdentityPhotoGenerationWorker.sidekiq_options.inspect}"
puts "Should track job: #{middleware.send(:should_track_job?, worker, job_data)}"

# Test the middleware call
puts "\n=== Testing Middleware Call ==="
puts "Instance ID: #{Sidekiq::ProcessingTracker.instance_id}"
puts "Namespace: #{Sidekiq::ProcessingTracker.namespace}"

begin
  # Check Redis connection
  Sidekiq::ProcessingTracker.redis_sync do |conn|
    puts "Redis connection: OK"
    puts "Redis info: #{conn.info['redis_version']}"
  end
  
  # Test middleware execution
  puts "\nExecuting job through middleware..."
  middleware.call(worker, job_data, "default") do
    puts "Job is executing..."
    
    # Check if job is being tracked during execution
    Sidekiq::ProcessingTracker.redis_sync do |conn|
      job_tracking_key = Sidekiq::ProcessingTracker.send(:namespaced_key, "jobs:#{Sidekiq::ProcessingTracker.instance_id}")
      job_data_key = Sidekiq::ProcessingTracker.send(:namespaced_key, "job:#{job_data['jid']}")
      
      is_tracked = conn.sismember(job_tracking_key, job_data["jid"])
      job_exists = conn.exists(job_data_key) > 0
      
      puts "Job #{job_data['jid']} is tracked: #{is_tracked}"
      puts "Job data exists in Redis: #{job_exists}"
      
      if job_exists
        stored_job = JSON.parse(conn.get(job_data_key))
        puts "Stored job data: #{stored_job.inspect}"
      end
    end
    
    # Simulate work
    sleep 1
  end
  
  puts "\nJob execution completed"
  
  # Check if job is cleaned up after execution
  Sidekiq::ProcessingTracker.redis_sync do |conn|
    job_tracking_key = Sidekiq::ProcessingTracker.send(:namespaced_key, "jobs:#{Sidekiq::ProcessingTracker.instance_id}")
    job_data_key = Sidekiq::ProcessingTracker.send(:namespaced_key, "job:#{job_data['jid']}")
    
    is_tracked = conn.sismember(job_tracking_key, job_data["jid"])
    job_exists = conn.exists(job_data_key) > 0
    
    puts "After execution - Job #{job_data['jid']} is tracked: #{is_tracked}"
    puts "After execution - Job data exists in Redis: #{job_exists}"
  end
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n")
end

puts "\n=== Test Complete ==="
