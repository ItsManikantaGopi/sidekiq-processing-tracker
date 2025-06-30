# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-06-20

### Added
- **Delayed Recovery System**: Configurable additional recovery passes for enhanced reliability
- **New Configuration Options**:
  - `ASSURED_JOBS_DELAYED_RECOVERY_INTERVAL`: Seconds between delayed recovery passes (default: 300)
  - `ASSURED_JOBS_DELAYED_RECOVERY_COUNT`: Number of delayed recovery passes to run (default: 1)

### Enhanced
- **Startup Recovery**: Improved startup process now includes delayed recovery thread spawning
- **Error Handling**: Enhanced error handling for delayed recovery operations
- **Documentation**: Comprehensive configuration reference with production recommendations

### Features
- **Background Recovery Threads**: Automatic spawning of delayed recovery threads after startup
- **Configurable Safety Net**: Multiple recovery passes to catch edge cases and network partition scenarios
- **Production Ready**: Optimized for high-availability and large-scale deployments

## [1.0.0] - 2025-06-18

### Added
- **Initial Release**: First public release of sidekiq-assured-jobs
- **Job Assurance**: Guarantees that critical Sidekiq jobs are never lost due to worker crashes
- **Automatic Recovery**: Detects and re-enqueues orphaned jobs from crashed workers
- **Production Ready**: Designed for high-throughput production environments
- **Zero Configuration**: Works out of the box with sensible defaults
- **Sidekiq Integration**: Uses Sidekiq's existing Redis connection pool
- **Distributed Locking**: Prevents duplicate recovery operations
- **Minimal Overhead**: Lightweight tracking with configurable heartbeat intervals

### Features
- **Job Tracking**: Tracks in-flight jobs in Redis with instance identification
- **Heartbeat System**: Monitors worker instance health with configurable intervals
- **Orphan Recovery**: Automatically re-enqueues jobs from crashed instances
- **Selective Tracking**: Only tracks workers that include the AssuredJobs::Worker module
- **SidekiqUniqueJobs Integration**: Automatically handles unique job lock clearing
- **Flexible Redis Configuration**: Uses Sidekiq's Redis by default, supports custom Redis

### Configuration Options
- `ASSURED_JOBS_INSTANCE_ID`: Unique instance identifier (auto-generated if not set)
- `ASSURED_JOBS_NS`: Redis namespace for keys (default: "sidekiq_assured_jobs")
- `ASSURED_JOBS_HEARTBEAT_INTERVAL`: Seconds between heartbeats (default: 15)
- `ASSURED_JOBS_HEARTBEAT_TTL`: Instance timeout threshold (default: 45)
- `ASSURED_JOBS_RECOVERY_LOCK_TTL`: Recovery operation lock duration (default: 300)

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
