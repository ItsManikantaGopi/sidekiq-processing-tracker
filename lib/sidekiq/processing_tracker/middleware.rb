# frozen_string_literal: true

module Sidekiq
  module ProcessingTracker
    class Middleware
      def call(worker, job, queue)
        # Log all jobs that go through the middleware
        worker_class = worker.is_a?(Class) ? worker : worker.class
        ProcessingTracker.logger.info "ProcessingTracker middleware called for #{worker_class.name} (#{job['jid']})"

        # Only track jobs that have processing: true option
        should_track = should_track_job?(worker, job)
        ProcessingTracker.logger.info "ProcessingTracker should track #{worker_class.name}: #{should_track}"

        return yield unless should_track

        jid = job["jid"]
        instance_id = ProcessingTracker.instance_id
        logger = ProcessingTracker.logger

        # Create tracking keys (using custom namespacing)
        job_tracking_key = ProcessingTracker.send(:namespaced_key, "jobs:#{instance_id}")
        job_data_key = ProcessingTracker.send(:namespaced_key, "job:#{jid}")

        begin
          # Add job to tracking set and store job payload
          begin
            ProcessingTracker.redis_sync do |conn|
              conn.multi do |multi|
                multi.sadd(job_tracking_key, jid)
                multi.set(job_data_key, job.to_json)
              end
            end
            logger.info "ProcessingTracker started tracking job #{jid} on instance #{instance_id}"
          rescue => e
            logger.error "ProcessingTracker failed to start tracking job #{jid}: #{e.message}"
            logger.error e.backtrace.join("\n")
          end

          # Execute the job
          yield
        ensure
          # Remove job from tracking
          begin
            ProcessingTracker.redis_sync do |conn|
              conn.multi do |multi|
                multi.srem(job_tracking_key, jid)
                multi.del(job_data_key)
              end
            end
            logger.info "ProcessingTracker stopped tracking job #{jid} on instance #{instance_id}"
          rescue => e
            logger.error "ProcessingTracker failed to stop tracking job #{jid}: #{e.message}"
          end
        end
      end

      private

      def should_track_job?(worker, job)
        # Check if the worker class has processing: true option
        worker_class = worker.is_a?(Class) ? worker : worker.class

        unless worker_class.respond_to?(:sidekiq_options)
          ProcessingTracker.logger.info "ProcessingTracker: #{worker_class.name} does not respond to sidekiq_options"
          return false
        end

        options = worker_class.sidekiq_options
        has_processing = options["processing"] == true

        ProcessingTracker.logger.info "ProcessingTracker: #{worker_class.name} sidekiq_options: #{options.inspect}"
        ProcessingTracker.logger.info "ProcessingTracker: #{worker_class.name} processing option: #{options['processing'].inspect}"

        has_processing
      end
    end
  end
end
