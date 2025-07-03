# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-01-03

### Added
- **🖥️ Web Dashboard**: Complete web interface for monitoring and managing orphaned jobs
- **📊 Real-time Monitoring**: Live dashboard showing all orphaned jobs with detailed information
- **🔄 Interactive Actions**: Manual retry and delete operations for individual jobs
- **🎯 Bulk Operations**: Select and manage multiple orphaned jobs simultaneously
- **📈 Instance Monitoring**: Visual status tracking of worker instances (alive/dead)
- **🔍 Job Details View**: Comprehensive job information including arguments, errors, and metadata
- **⏱️ Auto-refresh**: Dashboard automatically updates every 30 seconds
- **📱 Responsive Design**: Mobile-friendly interface matching Sidekiq's UI patterns

### Features
- **Orphaned Jobs Tab**: New tab in Sidekiq web interface at `/orphaned-jobs`
- **Job Arguments Display**: Arguments column in main table for better job identification
- **Bulk Selection**: Checkbox interface for selecting multiple jobs
- **Confirmation Dialogs**: Prevent accidental job deletions
- **Instance Health Cards**: Visual display of live vs dead worker instances
- **Job Duration Tracking**: Shows how long jobs have been orphaned
- **Error Information**: Display job errors and failure details
- **Demo Script**: Interactive demo at `examples/web_demo.rb`

### Technical
- **Web Extension**: Seamless integration with `Sidekiq::Web`
- **Helper Methods**: Time formatting, text truncation, CSRF protection
- **Data Access Layer**: Efficient Redis queries for orphaned job data
- **Test Coverage**: Comprehensive test suite for web functionality
- **Unicode Icons**: Replaced FontAwesome with Unicode symbols for better compatibility

### Documentation
- **Web Interface Guide**: Complete documentation of dashboard features
- **Setup Instructions**: Clear integration steps for Rails and standalone apps
- **Demo Instructions**: How to run the interactive demo
- **Feature Overview**: Detailed explanation of all web interface capabilities

## [1.0.0] - 2025-06-20

### Added
- **Initial Release**: First public release of sidekiq-assured-jobs
- **Job Assurance**: Guarantees that critical Sidekiq jobs are never lost due to worker crashes
- **Automatic Recovery**: Detects and re-enqueues orphaned jobs from crashed workers
- **Delayed Recovery System**: Configurable additional recovery passes for enhanced reliability
- **Production Ready**: Designed for high-throughput production environments
- **Zero Configuration**: Works out of the box with sensible defaults
- **Sidekiq Integration**: Uses Sidekiq's existing Redis connection pool
- **Distributed Locking**: Prevents duplicate recovery operations
- **Minimal Overhead**: Lightweight tracking with configurable heartbeat intervals

### Features
- **Job Tracking**: Tracks in-flight jobs in Redis with instance identification
- **Heartbeat System**: Monitors worker instance health with configurable intervals
- **Orphan Recovery**: Automatically re-enqueues jobs from crashed instances
- **Background Recovery Threads**: Automatic spawning of delayed recovery threads after startup
- **Configurable Safety Net**: Multiple recovery passes to catch edge cases and network partition scenarios
- **Selective Tracking**: Only tracks workers that include the AssuredJobs::Worker module
- **SidekiqUniqueJobs Integration**: Automatically handles unique job lock clearing
- **Flexible Redis Configuration**: Uses Sidekiq's Redis by default, supports custom Redis

### Configuration Options
- `ASSURED_JOBS_INSTANCE_ID`: Unique instance identifier (auto-generated if not set)
- `ASSURED_JOBS_NS`: Redis namespace for keys (default: "sidekiq_assured_jobs")
- `ASSURED_JOBS_HEARTBEAT_INTERVAL`: Seconds between heartbeats (default: 15)
- `ASSURED_JOBS_HEARTBEAT_TTL`: Instance timeout threshold (default: 45)
- `ASSURED_JOBS_RECOVERY_LOCK_TTL`: Recovery operation lock duration (default: 300)
- `ASSURED_JOBS_DELAYED_RECOVERY_INTERVAL`: Seconds between delayed recovery passes (default: 300)
- `ASSURED_JOBS_DELAYED_RECOVERY_COUNT`: Number of delayed recovery passes to run (default: 1)

### Dependencies
- Ruby >= 2.6.0
- Sidekiq >= 6.0, < 7
- Redis ~> 4.0

### Breaking Changes from sidekiq-processing-tracker
- **Gem Name**: Changed from `sidekiq-processing-tracker` to `sidekiq-assured-jobs`
- **Module Name**: Changed from `Sidekiq::ProcessingTracker` to `Sidekiq::AssuredJobs`
- **Worker Mixin**: Changed from `ProcessingTracker::Worker` to `AssuredJobs::Worker`
- **Sidekiq Option**: Changed from `processing: true` to `assured_jobs: true`
- **Environment Variables**: All prefixed with `ASSURED_JOBS_` instead of `PROCESSING_`
- **Default Namespace**: Changed from `sidekiq_processing` to `sidekiq_assured_jobs`
- **Logging**: Reduced verbose logging for production use
