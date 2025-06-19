# frozen_string_literal: true

module Sidekiq
  module AssuredJobs
    module Worker
      def self.included(base)
        base.extend(ClassMethods)
        base.sidekiq_options assured_jobs: true
      end

      module ClassMethods
        # Additional class methods can be added here if needed in the future
      end
    end
  end
end
