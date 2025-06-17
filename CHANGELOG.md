# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-06-17

### Added
- Initial release of sidekiq-processing-tracker
- Reliable in-flight job tracking for Sidekiq 6.x
- Automatic orphan job recovery in Kubernetes environments
- Per-pod instance identification with heartbeat monitoring
- Distributed locking for safe recovery operations
- Middleware for tracking job lifecycle
- Worker mixin for easy integration
- Comprehensive test suite with RSpec
- Full documentation with Mermaid diagrams
- Environment variable configuration
- Sidekiq server lifecycle hooks
- Redis-based job state persistence

### Features
- **Job Tracking**: Tracks in-flight jobs in Redis with instance identification
- **Heartbeat System**: Monitors worker pod health with configurable intervals
- **Orphan Recovery**: Automatically re-enqueues jobs from crashed pods
- **Distributed Locking**: Prevents concurrent recovery operations
- **Zero Configuration**: Works out of the box with sensible defaults
- **Kubernetes Ready**: Designed for containerized environments
- **Selective Tracking**: Only tracks workers that include the ProcessingTracker::Worker module

### Configuration Options
- `REDIS_URL`: Redis connection URL
- `PROCESSING_INSTANCE_ID`: Unique instance identifier
- `PROCESSING_NS`: Redis namespace for keys
- `HEARTBEAT_INTERVAL`: Seconds between heartbeats
- `HEARTBEAT_TTL`: Instance timeout threshold
- `RECOVERY_LOCK_TTL`: Recovery operation lock duration

### Dependencies
- Ruby >= 2.6.0
- Sidekiq >= 6.0, < 7
- Redis >= 4.0
