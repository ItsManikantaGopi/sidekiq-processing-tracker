# frozen_string_literal: true

require_relative "lib/sidekiq/assured_jobs/version"

Gem::Specification.new do |spec|
  spec.name = "sidekiq-assured-jobs"
  spec.version = Sidekiq::AssuredJobs::VERSION
  spec.authors = ["Manikanta Gopi"]
  spec.email = ["gopimanikanta50@gmail.com"]

  spec.summary = "Reliable job execution guarantee for Sidekiq with automatic orphan recovery"
  spec.description = "Ensures Sidekiq jobs are never lost due to worker crashes or restarts by tracking in-flight jobs and automatically recovering orphaned work"
  spec.homepage = "https://github.com/praja/sidekiq-assured-jobs"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/praja/sidekiq-assured-jobs"
  spec.metadata["changelog_uri"] = "https://github.com/praja/sidekiq-assured-jobs/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = [
    "lib/sidekiq-assured-jobs.rb",
    "lib/sidekiq/assured_jobs/version.rb",
    "lib/sidekiq/assured_jobs/middleware.rb",
    "lib/sidekiq/assured_jobs/worker.rb",
    "README.md",
    "LICENSE.txt",
    "CHANGELOG.md"
  ]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "sidekiq", ">= 6.0", "< 7"
  spec.add_dependency "redis", "~> 4.0"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
end
