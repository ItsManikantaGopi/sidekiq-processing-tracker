# Sidekiq Processing Tracker - Installation Guide

## 🚀 Quick Installation

### Option 1: From RubyGems (Recommended)
```bash
# Add to your Gemfile
gem 'sidekiq-processing-tracker'

# Then run
bundle install
```

### Option 2: From Source
```bash
# Clone the repository
git clone https://github.com/your-username/sidekiq-processing-tracker.git
cd sidekiq-processing-tracker

# Build and install the gem
gem build sidekiq-processing-tracker.gemspec
gem install sidekiq-processing-tracker-1.0.0.gem
```

## 🔧 Setup

### 1. Basic Setup (Zero Configuration)
```ruby
# In your application (e.g., config/application.rb or config/initializers/sidekiq.rb)
require 'sidekiq-processing-tracker'

# That's it! The gem auto-configures itself with sensible defaults
```

### 2. Custom Configuration (Optional)
```ruby
require 'sidekiq-processing-tracker'

Sidekiq::ProcessingTracker.configure do |config|
  config.namespace = "my_app_processing"
  config.heartbeat_interval = 45  # seconds
  config.heartbeat_ttl = 120      # seconds
  config.recovery_lock_ttl = 600  # seconds
end
```

### 3. Environment Variables (Kubernetes/Docker)
```yaml
# In your deployment.yaml
env:
- name: REDIS_URL
  value: "redis://redis-service:6379/0"
- name: PROCESSING_INSTANCE_ID
  valueFrom:
    fieldRef:
      fieldPath: metadata.name  # Use pod name as instance ID
- name: PROCESSING_NS
  value: "my_app_processing"
- name: HEARTBEAT_INTERVAL
  value: "30"
- name: HEARTBEAT_TTL
  value: "90"
```

## 👷 Worker Integration

### Enable Tracking for Specific Workers
```ruby
class CriticalDataProcessor
  include Sidekiq::Worker
  include Sidekiq::ProcessingTracker::Worker  # Add this line to enable tracking
  
  def perform(user_id, data)
    # This job will be tracked and recovered if the pod crashes
    process_critical_data(user_id, data)
  end
end

class RegularWorker
  include Sidekiq::Worker
  # No ProcessingTracker::Worker - this job won't be tracked
  
  def perform(message)
    # Regular job processing
  end
end
```

## 🐳 Docker/Kubernetes Deployment

### Dockerfile Example
```dockerfile
FROM ruby:3.1

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# The gem will auto-configure when the application starts
CMD ["bundle", "exec", "sidekiq"]
```

### Kubernetes Deployment Example
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sidekiq-workers
spec:
  replicas: 3
  selector:
    matchLabels:
      app: sidekiq-worker
  template:
    metadata:
      labels:
        app: sidekiq-worker
    spec:
      containers:
      - name: worker
        image: myapp:latest
        env:
        - name: PROCESSING_INSTANCE_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: REDIS_URL
          value: "redis://redis-service:6379/0"
        - name: HEARTBEAT_INTERVAL
          value: "30"
        - name: HEARTBEAT_TTL
          value: "90"
        command: ["bundle", "exec", "sidekiq"]
```

## 🔍 Verification

### Check if the gem is working
```ruby
# In a Rails console or Ruby script
require 'sidekiq-processing-tracker'

puts "Instance ID: #{Sidekiq::ProcessingTracker.instance_id}"
puts "Namespace: #{Sidekiq::ProcessingTracker.namespace}"
puts "Redis connected: #{Sidekiq::ProcessingTracker.redis.ping == 'PONG'}"
```

### Monitor Redis keys
```bash
# Connect to Redis and check for tracking keys
redis-cli

# Check for instance heartbeats
KEYS sidekiq_processing:instance:*

# Check for job tracking (when jobs are running)
KEYS sidekiq_processing:jobs:*

# Check for job payloads (when jobs are running)
KEYS sidekiq_processing:job:*
```

## 🚨 Troubleshooting

### Common Issues

**1. Gem build error: "contains itself"**
- Solution: Make sure you're not including the built `.gem` file in your repository
- The fixed gemspec explicitly lists only the necessary files

**2. Redis connection errors**
- Check that `REDIS_URL` is correctly set
- Verify Redis is accessible from your worker pods
- Ensure Redis version is 4.0 or higher

**3. Jobs not being tracked**
- Verify that workers include `Sidekiq::ProcessingTracker::Worker`
- Check that the middleware is properly registered (happens automatically)
- Look for error messages in Sidekiq logs

**4. Recovery not working**
- Check that multiple worker instances are running
- Verify heartbeat keys are being created in Redis
- Ensure recovery lock TTL is appropriate for your job volumes

### Debug Mode
```ruby
# Enable debug logging
Sidekiq::ProcessingTracker.configure do |config|
  config.logger.level = Logger::DEBUG
end
```

## 📊 Monitoring

### Key Metrics to Monitor
- Recovery operations frequency
- Redis memory usage
- Heartbeat failures
- Orphaned job counts

### Example Monitoring Queries
```ruby
# Check active instances
redis.keys("#{namespace}:instance:*").size

# Check tracked jobs
redis.keys("#{namespace}:jobs:*").map { |key| redis.scard(key) }.sum

# Check for recovery operations (look for log messages)
# "ProcessingTracker recovery lock acquired"
# "ProcessingTracker found X orphaned jobs"
```

## 🎯 Production Checklist

- [ ] Redis is properly configured and accessible
- [ ] Environment variables are set correctly
- [ ] Workers include the ProcessingTracker::Worker module
- [ ] Monitoring is set up for Redis and recovery operations
- [ ] Heartbeat intervals are tuned for your environment
- [ ] Recovery lock TTL is appropriate for your job volumes
- [ ] Logs are being collected and monitored

## 📞 Support

If you encounter issues:
1. Check the logs for error messages
2. Verify Redis connectivity and keys
3. Ensure proper worker configuration
4. Review the architecture documentation for understanding the system behavior

The gem is designed to be robust and self-healing, but proper monitoring and configuration are essential for production use.
