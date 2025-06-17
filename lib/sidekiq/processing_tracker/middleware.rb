# frozen_string_literal: true

module Sidekiq
  module ProcessingTracker
    class Middleware
      def call(worker, job, queue)
        # Only track jobs that have processing: true option
        return yield unless should_track_job?(worker, job)

        jid = job["jid"]
        instance_id = ProcessingTracker.instance_id
        namespace = ProcessingTracker.namespace
        redis = ProcessingTracker.redis
        logger = ProcessingTracker.logger

        # Create tracking keys
        job_tracking_key = "#{namespace}:jobs:#{instance_id}"
        job_data_key = "#{namespace}:job:#{jid}"

        begin
          # Add job to tracking set and store job payload
          redis.multi do |multi|
            multi.sadd(job_tracking_key, jid)
            multi.set(job_data_key, job.to_json)
          end

          logger.debug "ProcessingTracker started tracking job #{jid} on instance #{instance_id}"

          # Execute the job
          yield
        ensure
          # Remove job from tracking
          redis.multi do |multi|
            multi.srem(job_tracking_key, jid)
            multi.del(job_data_key)
          end

          logger.debug "ProcessingTracker stopped tracking job #{jid} on instance #{instance_id}"
        end
      end

      private

      def should_track_job?(worker, job)
        # Check if the worker class has processing: true option
        worker_class = worker.is_a?(Class) ? worker : worker.class
        return false unless worker_class.respond_to?(:sidekiq_options)

        options = worker_class.sidekiq_options
        options["processing"] == true
      end
    end
  end
end
