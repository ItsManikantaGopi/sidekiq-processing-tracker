# frozen_string_literal: true

require "sidekiq"
require "redis"
require "logger"
require "securerandom"
require "set"

require_relative "sidekiq/assured_jobs/version"
require_relative "sidekiq/assured_jobs/middleware"
require_relative "sidekiq/assured_jobs/worker"

# Optionally load web extension if Sidekiq::Web is available
begin
  require "sidekiq/web"
  require_relative "sidekiq/assured_jobs/web"
rescue LoadError
  # Sidekiq::Web not available, skip web extension
end

module Sidekiq
  module AssuredJobs
    class Error < StandardError; end

    class << self
      attr_accessor :instance_id, :namespace, :heartbeat_interval, :heartbeat_ttl, :recovery_lock_ttl, :logger, :redis_options, :delayed_recovery_count, :delayed_recovery_interval

      def configure
        yield self if block_given?
        setup_defaults
        setup_sidekiq_hooks
      end

      def redis(&block)
        if redis_options
          # Use custom Redis configuration if provided
          redis_client = Redis.new(redis_options)
          if block_given?
            result = yield redis_client
            redis_client.close
            result
          else
            redis_client
          end
        else
          # Use Sidekiq's Redis connection pool
          Sidekiq.redis(&block)
        end
      end

      def redis_sync(&block)
        # Synchronous Redis operations using Sidekiq's pool or custom config
        redis(&block)
      end

      # Helper method to add namespace prefix to Redis keys
      def namespaced_key(key)
        "#{namespace}:#{key}"
      end

      # Clear unique-jobs lock for orphaned jobs to allow immediate re-enqueuing
      def clear_unique_jobs_lock(job_data)
        return unless job_data['unique_digest']

        begin
          # Check if SidekiqUniqueJobs is available
          if defined?(SidekiqUniqueJobs::Digests)
            SidekiqUniqueJobs::Digests.del(digest: job_data['unique_digest'])
            logger.info "AssuredJobs cleared unique-jobs lock for job #{job_data['jid']} with digest #{job_data['unique_digest']}"
          else
            logger.debug "AssuredJobs: SidekiqUniqueJobs not available, skipping lock cleanup for job #{job_data['jid']}"
          end
        rescue => e
          logger.warn "AssuredJobs failed to clear unique-jobs lock for job #{job_data['jid']}: #{e.message}"
        end
      end

      def reenqueue_orphans!
        with_recovery_lock do
          logger.info "AssuredJobs starting orphan job recovery"

          redis_sync do |conn|
            # Get all job keys and instance keys (using custom namespacing)
            job_keys = conn.keys(namespaced_key("jobs:*"))
            instance_keys = conn.keys(namespaced_key("instance:*"))

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
                  job_data_key = namespaced_key("job:#{jid}")
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
              logger.info "AssuredJobs found #{orphaned_jobs.size} orphaned jobs, re-enqueuing"
              orphaned_jobs.each do |job_data|
                # Clear unique-jobs lock before re-enqueuing to avoid lock conflicts
                clear_unique_jobs_lock(job_data)

                Sidekiq::Client.push(job_data)
                logger.info "AssuredJobs re-enqueued job #{job_data['jid']} (#{job_data['class']})"
              end
            else
              logger.info "AssuredJobs found no orphaned jobs"
            end
          end
        end
      rescue => e
        logger.error "AssuredJobs orphan recovery failed: #{e.message}"
        logger.error e.backtrace.join("\n")
      end

      # Web interface support methods
      def get_orphaned_jobs_info
        orphaned_jobs = []

        redis_sync do |conn|
          # Get all job keys and instance keys
          job_keys = conn.keys(namespaced_key("jobs:*"))
          instance_keys = conn.keys(namespaced_key("instance:*"))

          # Extract live instance IDs
          live_instances = instance_keys.map { |key| key.split(":").last }.to_set

          job_keys.each do |job_key|
            instance_id = job_key.split(":").last
            unless live_instances.include?(instance_id)
              # Get all job IDs for this dead instance
              job_ids = conn.smembers(job_key)

              job_ids.each do |jid|
                job_data_key = namespaced_key("job:#{jid}")
                job_payload = conn.get(job_data_key)

                if job_payload
                  job_data = JSON.parse(job_payload)
                  job_data['instance_id'] = instance_id
                  job_data['orphaned_at'] = get_instance_last_heartbeat(instance_id, conn)
                  job_data['orphaned_duration'] = calculate_orphaned_duration(job_data['orphaned_at'])
                  orphaned_jobs << job_data
                end
              end
            end
          end
        end

        orphaned_jobs.sort_by { |job| job['orphaned_at'] || 0 }.reverse
      end

      def get_instances_status
        instances = {}

        redis_sync do |conn|
          # Get live instances
          instance_keys = conn.keys(namespaced_key("instance:*"))
          instance_keys.each do |key|
            instance_id = key.split(":").last
            heartbeat = conn.get(key)
            instances[instance_id] = {
              status: 'alive',
              last_heartbeat: heartbeat ? Time.at(heartbeat.to_f) : nil
            }
          end

          # Get dead instances with orphaned jobs
          job_keys = conn.keys(namespaced_key("jobs:*"))
          job_keys.each do |job_key|
            instance_id = job_key.split(":").last
            unless instances[instance_id]
              instances[instance_id] = {
                status: 'dead',
                last_heartbeat: get_instance_last_heartbeat(instance_id, conn),
                orphaned_job_count: conn.scard(job_key)
              }
            end
          end
        end

        instances
      end

      def get_orphaned_job_by_jid(jid)
        redis_sync do |conn|
          job_data_key = namespaced_key("job:#{jid}")
          job_payload = conn.get(job_data_key)

          if job_payload
            job_data = JSON.parse(job_payload)

            # Find which instance this job belongs to
            job_keys = conn.keys(namespaced_key("jobs:*"))
            job_keys.each do |job_key|
              if conn.sismember(job_key, jid)
                instance_id = job_key.split(":").last
                job_data['instance_id'] = instance_id
                job_data['orphaned_at'] = get_instance_last_heartbeat(instance_id, conn)
                job_data['orphaned_duration'] = calculate_orphaned_duration(job_data['orphaned_at'])
                break
              end
            end

            job_data
          end
        end
      end

      def setup_sidekiq_hooks
        return unless defined?(Sidekiq::VERSION)

        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add AssuredJobs::Middleware
          end

          # Add startup hook for heartbeat and orphan recovery
          config.on(:startup) do
            # Ensure configuration is set up
            setup_defaults unless @instance_id

            logger.info "AssuredJobs starting up on instance #{instance_id}"

            # Start heartbeat system
            setup_heartbeat

            # Run orphan recovery on startup only
            Thread.new do
              sleep 5 # Give the server a moment to fully start
              begin
                reenqueue_orphans!
                spinup_delayed_recovery_thread
              rescue => e
                logger.error "AssuredJobs startup orphan recovery failed: #{e.message}"
                logger.error e.backtrace.join("\n")
              end
            end
          end

          # Add shutdown hook to clean up
          config.on(:shutdown) do
            logger.info "AssuredJobs shutting down instance #{instance_id}"
            begin
              # Stop heartbeat thread
              if @heartbeat_thread&.alive?
                @heartbeat_thread.kill
                @heartbeat_thread = nil
              end

              redis_sync do |conn|
                # Only clean up instance heartbeat - let orphan recovery handle job cleanup
                # This ensures that if there are running jobs during shutdown, they will be
                # detected as orphaned and recovered by the next instance
                conn.del(namespaced_key("instance:#{instance_id}"))

                # Log tracked jobs but don't clean them up - they should be recovered as orphans
                job_tracking_key = namespaced_key("jobs:#{instance_id}")
                tracked_jobs = conn.smembers(job_tracking_key)

                if tracked_jobs.any?
                  logger.warn "AssuredJobs leaving #{tracked_jobs.size} tracked jobs for orphan recovery: #{tracked_jobs.join(', ')}"
                  logger.info "AssuredJobs: These jobs will be recovered by the next instance startup"
                else
                  logger.info "AssuredJobs: No tracked jobs to leave for recovery"
                end
              end
            rescue => e
              logger.error "AssuredJobs shutdown cleanup failed: #{e.message}"
            end
          end
        end
      end

      private

      def setup_defaults
        @instance_id ||= ENV.fetch("ASSURED_JOBS_INSTANCE_ID") { SecureRandom.hex(8) }
        @namespace ||= ENV.fetch("ASSURED_JOBS_NS", "sidekiq_assured_jobs")
        @heartbeat_interval ||= ENV.fetch("ASSURED_JOBS_HEARTBEAT_INTERVAL", "15").to_i
        @heartbeat_ttl ||= ENV.fetch("ASSURED_JOBS_HEARTBEAT_TTL", "45").to_i
        @recovery_lock_ttl ||= ENV.fetch("ASSURED_JOBS_RECOVERY_LOCK_TTL", "300").to_i
        @logger ||= Sidekiq.logger
        @delayed_recovery_count ||= ENV.fetch("ASSURED_JOBS_DELAYED_RECOVERY_COUNT", "1").to_i
        @delayed_recovery_interval ||= ENV.fetch("ASSURED_JOBS_DELAYED_RECOVERY_INTERVAL", "300").to_i
      end

      def setup_heartbeat
        # Initial heartbeat
        send_heartbeat

        # Background heartbeat thread
        @heartbeat_thread = Thread.new do
          loop do
            sleep heartbeat_interval
            begin
              send_heartbeat
            rescue => e
              logger.error "AssuredJobs heartbeat failed: #{e.message}"
            end
          end
        end
      end

      def send_heartbeat
        key = namespaced_key("instance:#{instance_id}")
        redis_sync do |conn|
          conn.setex(key, heartbeat_ttl, Time.now.to_f)
        end
        logger.debug "AssuredJobs heartbeat sent for instance #{instance_id}"
      end

      def spinup_delayed_recovery_thread
        Thread.new do
          @delayed_recovery_count.times do |i|
            sleep @delayed_recovery_interval
            begin
              reenqueue_orphans!
            rescue => e
              logger.error(
                "[AssuredJobs] delayed recovery ##{i+1} failed: #{e.message}"
              )
            end
          end
        end
      end
      def with_recovery_lock
        lock_key = namespaced_key("recovery_lock")
        lock_acquired = redis_sync do |conn|
          conn.set(lock_key, instance_id, nx: true, ex: recovery_lock_ttl)
        end

        if lock_acquired
          logger.info "AssuredJobs recovery lock acquired by instance #{instance_id}"
          begin
            yield
          ensure
            redis_sync { |conn| conn.del(lock_key) }
            logger.info "AssuredJobs recovery lock released by instance #{instance_id}"
          end
        else
          logger.debug "AssuredJobs recovery lock not acquired, another instance is handling recovery"
        end
      end

      def get_instance_last_heartbeat(instance_id, conn = nil)
        operation = proc do |redis_conn|
          key = namespaced_key("instance:#{instance_id}")
          heartbeat = redis_conn.get(key)
          return heartbeat.to_f if heartbeat

          # If no heartbeat found, estimate based on TTL
          Time.now.to_f - heartbeat_ttl
        end

        if conn
          operation.call(conn)
        else
          redis_sync(&operation)
        end
      end

      def calculate_orphaned_duration(orphaned_at)
        return nil unless orphaned_at
        Time.now.to_f - orphaned_at.to_f
      end
    end
  end
end

# Auto-setup defaults and Sidekiq hooks when gem is required
Sidekiq::AssuredJobs.send(:setup_defaults)
Sidekiq::AssuredJobs.setup_sidekiq_hooks
