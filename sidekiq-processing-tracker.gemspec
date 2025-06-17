# frozen_string_literal: true

require_relative "lib/sidekiq/processing_tracker/version"

Gem::Specification.new do |spec|
  spec.name = "sidekiq-processing-tracker"
  spec.version = Sidekiq::ProcessingTracker::VERSION
  spec.authors = ["Sidekiq Processing Tracker Team"]
  spec.email = ["team@example.com"]

  spec.summary = "Reliable in-flight job tracking for Sidekiq 6.x on Kubernetes"
  spec.description = "Provides robust tracking of in-flight Sidekiq jobs with automatic recovery of orphaned jobs in Kubernetes environments"
  spec.homepage = "https://github.com/example/sidekiq-processing-tracker"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/example/sidekiq-processing-tracker"
  spec.metadata["changelog_uri"] = "https://github.com/example/sidekiq-processing-tracker/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = [
    "lib/sidekiq-processing-tracker.rb",
    "lib/sidekiq/processing_tracker/version.rb",
    "lib/sidekiq/processing_tracker/middleware.rb",
    "lib/sidekiq/processing_tracker/worker.rb",
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
