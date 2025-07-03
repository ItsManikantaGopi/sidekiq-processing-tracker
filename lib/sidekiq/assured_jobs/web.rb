# frozen_string_literal: true

require 'sidekiq/web'

module Sidekiq
  module AssuredJobs
    module Web
      def self.registered(app)
        # Add helper methods to the app
        app.helpers do
          def relative_time(time)
            return 'Unknown' unless time

            diff = Time.now - time
            case diff
            when 0..59
              "#{diff.to_i} seconds ago"
            when 60..3599
              "#{(diff / 60).to_i} minutes ago"
            when 3600..86399
              "#{(diff / 3600).to_i} hours ago"
            else
              "#{(diff / 86400).to_i} days ago"
            end
          end

          def distance_of_time_in_words(seconds)
            return 'Unknown' unless seconds

            case seconds
            when 0..59
              "#{seconds.to_i}s"
            when 60..3599
              "#{(seconds / 60).to_i}m"
            when 3600..86399
              "#{(seconds / 3600).to_i}h"
            else
              "#{(seconds / 86400).to_i}d"
            end
          end

          def truncate(text, length)
            return text unless text
            text.length > length ? "#{text[0, length]}..." : text
          end

          def csrf_tag
            # Sidekiq web uses Rack::Protection, get the token
            "<input type='hidden' name='authenticity_token' value='#{env['rack.session'][:csrf]}' />"
          end

          def root_path
            "#{env['SCRIPT_NAME']}/"
          end
        end

        app.get '/orphaned-jobs' do
          @orphaned_jobs = OrphanedJobsManager.get_orphaned_jobs
          @instances = OrphanedJobsManager.get_instances_info
          @total_count = @orphaned_jobs.size
          erb File.read(File.join(File.dirname(__FILE__), '../../../web/views/orphaned_jobs.erb'))
        end

        app.get '/orphaned-jobs/:jid' do
          jid = params[:jid]
          @job = OrphanedJobsManager.get_orphaned_job(jid)
          halt 404 unless @job
          erb File.read(File.join(File.dirname(__FILE__), '../../../web/views/orphaned_job.erb'))
        end

        app.post '/orphaned-jobs/:jid/retry' do
          jid = params[:jid]
          result = OrphanedJobsManager.retry_orphaned_job(jid)
          if result[:success]
            redirect to('/orphaned-jobs')
          else
            halt 400, result[:error]
          end
        end

        app.post '/orphaned-jobs/:jid/delete' do
          jid = params[:jid]
          result = OrphanedJobsManager.delete_orphaned_job(jid)
          if result[:success]
            redirect to('/orphaned-jobs')
          else
            halt 400, result[:error]
          end
        end

        app.post '/orphaned-jobs/bulk-action' do
          action = params[:action]
          jids = params[:jids] || []
          
          case action
          when 'retry'
            result = OrphanedJobsManager.bulk_retry_orphaned_jobs(jids)
          when 'delete'
            result = OrphanedJobsManager.bulk_delete_orphaned_jobs(jids)
          else
            halt 400, "Invalid action: #{action}"
          end

          if result[:success]
            redirect to('/orphaned-jobs')
          else
            halt 400, result[:error]
          end
        end

        app.get '/orphaned-jobs/stats' do
          content_type :json
          OrphanedJobsManager.get_stats.to_json
        end
      end

      # Manager class for handling orphaned jobs operations
      class OrphanedJobsManager
        class << self
          def get_orphaned_jobs
            AssuredJobs.get_orphaned_jobs_info
          end

          def get_orphaned_job(jid)
            AssuredJobs.get_orphaned_job_by_jid(jid)
          end

          def retry_orphaned_job(jid)
            begin
              job_data = get_orphaned_job(jid)
              return { success: false, error: "Job not found" } unless job_data

              # Clear unique-jobs lock if present
              AssuredJobs.clear_unique_jobs_lock(job_data)
              
              # Re-enqueue the job
              Sidekiq::Client.push(job_data)
              
              # Clean up tracking data
              cleanup_job_tracking(jid, job_data['instance_id'])
              
              { success: true }
            rescue => e
              { success: false, error: e.message }
            end
          end

          def delete_orphaned_job(jid)
            begin
              job_data = get_orphaned_job(jid)
              return { success: false, error: "Job not found" } unless job_data

              # Clean up tracking data
              cleanup_job_tracking(jid, job_data['instance_id'])
              
              { success: true }
            rescue => e
              { success: false, error: e.message }
            end
          end

          def bulk_retry_orphaned_jobs(jids)
            begin
              success_count = 0
              errors = []
              
              jids.each do |jid|
                result = retry_orphaned_job(jid)
                if result[:success]
                  success_count += 1
                else
                  errors << "#{jid}: #{result[:error]}"
                end
              end
              
              if errors.empty?
                { success: true, message: "Successfully retried #{success_count} jobs" }
              else
                { success: false, error: "Retried #{success_count} jobs, failed: #{errors.join(', ')}" }
              end
            rescue => e
              { success: false, error: e.message }
            end
          end

          def bulk_delete_orphaned_jobs(jids)
            begin
              success_count = 0
              errors = []
              
              jids.each do |jid|
                result = delete_orphaned_job(jid)
                if result[:success]
                  success_count += 1
                else
                  errors << "#{jid}: #{result[:error]}"
                end
              end
              
              if errors.empty?
                { success: true, message: "Successfully deleted #{success_count} jobs" }
              else
                { success: false, error: "Deleted #{success_count} jobs, failed: #{errors.join(', ')}" }
              end
            rescue => e
              { success: false, error: e.message }
            end
          end

          def get_instances_info
            AssuredJobs.get_instances_status
          end

          def get_stats
            stats = {
              total_orphaned_jobs: 0,
              dead_instances: 0,
              live_instances: 0,
              oldest_orphaned_job: nil
            }
            
            orphaned_jobs = get_orphaned_jobs
            instances = get_instances_info
            
            stats[:total_orphaned_jobs] = orphaned_jobs.size
            stats[:dead_instances] = instances.count { |_, info| info[:status] == 'dead' }
            stats[:live_instances] = instances.count { |_, info| info[:status] == 'alive' }
            
            if orphaned_jobs.any?
              oldest_job = orphaned_jobs.min_by { |job| job['orphaned_at'] || Float::INFINITY }
              stats[:oldest_orphaned_job] = oldest_job['orphaned_duration'] if oldest_job
            end
            
            stats
          end

          private

          def cleanup_job_tracking(jid, instance_id)
            AssuredJobs.redis_sync do |conn|
              job_tracking_key = AssuredJobs.send(:namespaced_key, "jobs:#{instance_id}")
              job_data_key = AssuredJobs.send(:namespaced_key, "job:#{jid}")

              conn.multi do |multi|
                multi.srem(job_tracking_key, jid)
                multi.del(job_data_key)
              end
            end
          end
        end
      end
    end
  end
end

# Register the web extension with Sidekiq::Web
Sidekiq::Web.register(Sidekiq::AssuredJobs::Web)
Sidekiq::Web.tabs["Orphaned Jobs"] = "orphaned-jobs"
