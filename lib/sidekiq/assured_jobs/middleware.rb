# frozen_string_literal: true

module Sidekiq
  module AssuredJobs
    class Middleware
      def call(worker, job, queue)
        # Only track jobs that have assured_jobs: true option
        should_track = should_track_job?(worker, job)
        
        return yield unless should_track

        jid = job["jid"]
        instance_id = AssuredJobs.instance_id
        logger = AssuredJobs.logger

        # Create tracking keys (using custom namespacing)
        job_tracking_key = AssuredJobs.send(:namespaced_key, "jobs:#{instance_id}")
        job_data_key = AssuredJobs.send(:namespaced_key, "job:#{jid}")

        begin
          # Add job to tracking set and store job payload
          begin
            AssuredJobs.redis_sync do |conn|
              conn.multi do |multi|
                multi.sadd(job_tracking_key, jid)
                multi.set(job_data_key, job.to_json)
              end
            end
            logger.debug "AssuredJobs started tracking job #{jid} on instance #{instance_id}"
          rescue => e
            logger.error "AssuredJobs failed to start tracking job #{jid}: #{e.message}"
            logger.error e.backtrace.join("\n")
          end

          # Execute the job
          yield
        ensure
          # Remove job from tracking
          begin
            AssuredJobs.redis_sync do |conn|
              conn.multi do |multi|
                multi.srem(job_tracking_key, jid)
                multi.del(job_data_key)
              end
            end
            logger.debug "AssuredJobs stopped tracking job #{jid} on instance #{instance_id}"
          rescue => e
            logger.error "AssuredJobs failed to stop tracking job #{jid}: #{e.message}"
          end
        end
      end

      private

      def should_track_job?(worker, job)
        # Check if the worker class has assured_jobs: true option
        worker_class = worker.is_a?(Class) ? worker : worker.class

        unless worker_class.respond_to?(:sidekiq_options)
          return false
        end

        options = worker_class.sidekiq_options
        options["assured_jobs"] == true
      end
    end
  end
end
