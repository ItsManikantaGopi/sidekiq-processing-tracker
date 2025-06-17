# frozen_string_literal: true

require "sidekiq"
require "redis"
require "logger"
require "securerandom"

require_relative "sidekiq/processing_tracker/version"
require_relative "sidekiq/processing_tracker/middleware"
require_relative "sidekiq/processing_tracker/worker"

module Sidekiq
  module ProcessingTracker
    class Error < StandardError; end

    class << self
      attr_accessor :instance_id, :namespace, :heartbeat_interval, :heartbeat_ttl, :recovery_lock_ttl, :logger

      def configure
        yield self if block_given?
        setup_defaults
        setup_heartbeat
        setup_sidekiq_hooks
      end

      def redis
        # Use Sidekiq's Redis connection pool
        Sidekiq.redis_pool.with { |conn| yield conn } if block_given?
        Sidekiq.redis_pool
      end

      def redis_sync(&block)
        # Synchronous Redis operations using Sidekiq's pool
        Sidekiq.redis(&block)
      end

      def reenqueue_orphans!
        with_recovery_lock do
          logger.info "ProcessingTracker starting orphan job recovery"

          redis_sync do |conn|
            # Get all job keys and instance keys
            job_keys = conn.keys("#{namespace}:jobs:*")
            instance_keys = conn.keys("#{namespace}:instance:*")

            # Extract instance IDs from keys
            live_instances = instance_keys.map { |key| key.split(":").last }.to_set

            orphaned_jobs = []

            job_keys.each do |job_key|
              instance_id = job_key.split(":").last
              unless live_instances.include?(instance_id)
                # Get all job IDs for this dead instance
                job_ids = conn.smembers(job_key)

                job_ids.each do |jid|
                  # Get the job payload
                  job_data_key = "#{namespace}:job:#{jid}"
                  job_payload = conn.get(job_data_key)

                  if job_payload
                    orphaned_jobs << JSON.parse(job_payload)
                    # Clean up the job data key
                    conn.del(job_data_key)
                  end
                end

                # Clean up the job tracking key
                conn.del(job_key)
              end
            end

            if orphaned_jobs.any?
              logger.info "ProcessingTracker found #{orphaned_jobs.size} orphaned jobs, re-enqueuing"
              orphaned_jobs.each do |job_data|
                Sidekiq::Client.push(job_data)
                logger.debug "ProcessingTracker re-enqueued job #{job_data['jid']}"
              end
            else
              logger.info "ProcessingTracker found no orphaned jobs"
            end
          end
        end
      rescue => e
        logger.error "ProcessingTracker orphan recovery failed: #{e.message}"
        logger.error e.backtrace.join("\n")
      end

      private

      def setup_defaults
        @instance_id ||= ENV.fetch("PROCESSING_INSTANCE_ID") { SecureRandom.hex(8) }
        @namespace ||= ENV.fetch("PROCESSING_NS", "sidekiq_processing")
        @heartbeat_interval ||= ENV.fetch("HEARTBEAT_INTERVAL", "30").to_i
        @heartbeat_ttl ||= ENV.fetch("HEARTBEAT_TTL", "90").to_i
        @recovery_lock_ttl ||= ENV.fetch("RECOVERY_LOCK_TTL", "300").to_i
        @logger ||= Sidekiq.logger
      end

      def setup_heartbeat
        start_heartbeat_thread
      end

      def setup_sidekiq_hooks
        return unless defined?(Sidekiq::VERSION)

        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add ProcessingTracker::Middleware
          end

          # Add startup hook for orphan recovery
          config.on(:startup) do
            logger.info "ProcessingTracker starting up on instance #{instance_id}"

            # Run orphan recovery in a separate thread to avoid blocking startup
            Thread.new do
              sleep 5 # Give the server a moment to fully start
              begin
                reenqueue_orphans!
              rescue => e
                logger.error "ProcessingTracker startup orphan recovery failed: #{e.message}"
                logger.error e.backtrace.join("\n")
              end
            end
          end

          # Add shutdown hook to clean up
          config.on(:shutdown) do
            logger.info "ProcessingTracker shutting down instance #{instance_id}"
            begin
              redis_sync do |conn|
                # Clean up instance heartbeat
                conn.del("#{namespace}:instance:#{instance_id}")

                # Clean up any remaining job tracking for this instance
                job_tracking_key = "#{namespace}:jobs:#{instance_id}"
                tracked_jobs = conn.smembers(job_tracking_key)

                if tracked_jobs.any?
                  logger.warn "ProcessingTracker cleaning up #{tracked_jobs.size} tracked jobs on shutdown"
                  tracked_jobs.each do |jid|
                    conn.del("#{namespace}:job:#{jid}")
                  end
                  conn.del(job_tracking_key)
                end
              end
            rescue => e
              logger.error "ProcessingTracker shutdown cleanup failed: #{e.message}"
            end
          end
        end
      end

      def start_heartbeat_thread
        # Initial heartbeat
        send_heartbeat

        # Background heartbeat thread
        Thread.new do
          loop do
            sleep heartbeat_interval
            begin
              send_heartbeat
            rescue => e
              logger.error "ProcessingTracker heartbeat failed: #{e.message}"
            end
          end
        end
      end

      def send_heartbeat
        key = "#{namespace}:instance:#{instance_id}"
        redis_sync do |conn|
          conn.setex(key, heartbeat_ttl, Time.now.to_f)
        end
        logger.debug "ProcessingTracker heartbeat sent for instance #{instance_id}"
      end

      def with_recovery_lock
        lock_key = "#{namespace}:recovery_lock"
        lock_acquired = redis_sync do |conn|
          conn.set(lock_key, instance_id, nx: true, ex: recovery_lock_ttl)
        end

        if lock_acquired
          logger.info "ProcessingTracker recovery lock acquired by instance #{instance_id}"
          begin
            yield
          ensure
            redis_sync { |conn| conn.del(lock_key) }
            logger.info "ProcessingTracker recovery lock released by instance #{instance_id}"
          end
        else
          logger.debug "ProcessingTracker recovery lock not acquired, another instance is handling recovery"
        end
      end


    end
  end
end

# Auto-configure when required
Sidekiq::ProcessingTracker.configure
