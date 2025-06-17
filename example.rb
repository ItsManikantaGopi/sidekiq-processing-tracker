#!/usr/bin/env ruby
# frozen_string_literal: true

# Example usage of sidekiq-processing-tracker
require_relative "lib/sidekiq-processing-tracker"

# Example worker that will be tracked
class ImportantDataProcessor
  include Sidekiq::Worker
  include Sidekiq::ProcessingTracker::Worker  # This enables tracking

  def perform(user_id, data_type)
    puts "Processing #{data_type} for user #{user_id}"
    sleep 2 # Simulate work
    puts "Completed processing #{data_type} for user #{user_id}"
  end
end

# Example worker that won't be tracked
class SimpleWorker
  include Sidekiq::Worker
  # No ProcessingTracker::Worker included

  def perform(message)
    puts "Simple work: #{message}"
  end
end

# Configure the tracker (optional - it auto-configures)
Sidekiq::ProcessingTracker.configure do |config|
  config.namespace = "example_app_processing"
  config.heartbeat_interval = 30
  config.heartbeat_ttl = 90
end

puts "Sidekiq Processing Tracker Example"
puts "=================================="
puts "Instance ID: #{Sidekiq::ProcessingTracker.instance_id}"
puts "Namespace: #{Sidekiq::ProcessingTracker.namespace}"
puts "Heartbeat Interval: #{Sidekiq::ProcessingTracker.heartbeat_interval}s"
puts "Heartbeat TTL: #{Sidekiq::ProcessingTracker.heartbeat_ttl}s"
puts ""
puts "Workers configured:"
puts "- ImportantDataProcessor: TRACKED (includes ProcessingTracker::Worker)"
puts "- SimpleWorker: NOT TRACKED (regular Sidekiq worker)"
puts ""
puts "To test the gem:"
puts "1. Start Redis: redis-server"
puts "2. Start Sidekiq: bundle exec sidekiq -r ./example.rb"
puts "3. Enqueue jobs in another terminal:"
puts "   ImportantDataProcessor.perform_async(123, 'user_data')"
puts "   SimpleWorker.perform_async('hello world')"
puts ""
puts "The gem will automatically track ImportantDataProcessor jobs and"
puts "recover them if the worker pod crashes during processing."
