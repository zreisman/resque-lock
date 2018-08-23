module Resque
  module Plugins
    # If you want only one instance of your job queued at a time,
    # extend it with this module.
    #
    # For example:
    #
    # require 'resque/plugins/lock'
    #
    # class UpdateNetworkGraph
    #   extend Resque::Plugins::Lock
    #
    #   def self.perform(repo_id)
    #     heavy_lifting
    #   end
    # end
    #
    # No other UpdateNetworkGraph jobs will be placed on the queue,
    # the QueueLock class will check Redis to see if any others are
    # queued with the same arguments before queueing. If another
    # is queued the enqueue will be aborted.
    #
    # If you want to define the key yourself you can override the
    # `lock` class method in your subclass, e.g.
    #
    # class UpdateNetworkGraph
    #   extend Resque::Plugins::Lock
    #
    #   # Run only one at a time, regardless of repo_id.
    #   def self.lock(repo_id)
    #     "network-graph"
    #   end
    #
    #   def self.perform(repo_id)
    #     heavy_lifting
    #   end
    # end
    #
    # The above modification will ensure only one job of class
    # UpdateNetworkGraph is running at a time, regardless of the
    # repo_id. Normally a job is locked using a combination of its
    # class name and arguments.
    module Lock

      # Override in your job to control the lock experiation time. This is the
      # time in seconds that the lock should be considered valid. The default
      # is one hour (3600 seconds).
      def lock_timeout
        3600
      end

      # Override in your job to control the lock key. It is
      # passed the same arguments as `perform`, that is, your job's
      # payload.
      def lock(*args)
        args.map! { |a| a.is_a?(Symbol) ? a.to_s : a }
        "lock:#{name}-#{args.to_s}"
      end

      # See the documentation for SETNX http://redis.io/commands/setnx for an
      # explanation of this deadlock free locking pattern
      def before_enqueue_lock(*args)
        key = lock(*args)
        now = Time.now.to_i
        timeout = now + lock_timeout + 1

        # return true if we successfully acquired the lock
        return true if Resque.redis.setnx(key, timeout)

        # see if the existing timeout is still valid and return false if it is
        # (we cannot acquire the lock during the timeout period)
        return false if now <= Resque.redis.get(key).to_i

        # otherwise set the timeout and ensure that no other worker has
        # acquired the lock
        now > Resque.redis.getset(key, timeout).to_i
      end

      def around_perform_lock(*args)
        begin
          yield
        ensure
          # Always clear the lock when we're done, even if there is an
          # error.
          Resque.redis.del(lock(*args))
        end
      end
    end
  end
end

