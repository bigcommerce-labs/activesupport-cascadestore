require 'monitor'

module ActiveSupport
  module Cache
    # A thread-safe cache store implementation that cascades
    # operations to a list of other cache stores. It is used to
    # provide fallback cache stores when primary stores become
    # unavailable. For example, to initialize a CascadeStore that
    # cascades through MemCacheStore, MemoryStore, and FileStore:
    #
    #     ActiveSupport::Cache.lookup_store(:cascade_store,
    #       :stores => [
    #         :mem_cache_store,
    #         :memory_store,
    #         :file_store
    #       ]
    #     })
    #
    # Cache operation behavior:
    #
    # Read: returns first cache hit from :stores, nil if none found
    #
    # Write/Delete: write/delete through to each cache store in
    # :stores
    #
    # Increment/Decrement: increment/decrement each store, returning
    # the new number if any stores was successfully
    # incremented/decremented, nil otherwise
    class CascadeStore < Store
      attr_reader :stores

      # Initialize a CascadeStore with +options[:stores]+, an array of
      # options to initialize other ActiveSupport::Cache::Store
      # implementations.  If options is a symbol, top level
      # CascadeStore options are used for cascaded stores. If options
      # is an array, they are passed on unchanged.
      def initialize(options = nil, &blk)
        options ||= {}
        super(options)
        @monitor = Monitor.new
        store_options = options.delete(:stores) || []
        @stores = store_options.map do |o|
          o = o.is_a?(Symbol) ? [o, options] : o
          ActiveSupport::Cache.lookup_store(*o)
        end
      end

      def increment(name, amount = 1, options = nil)
        nums = cascade(:increment, name, amount, options)
        nums.detect {|n| !n.nil?}
      end

      def decrement(name, amount = 1, options = nil)
        nums = cascade(:decrement, name, amount, options)
        nums.detect {|n| !n.nil?}
      end

      def delete_matched(matcher, options = nil)
        cascade(:delete_matched, matcher, options)
        nil
      end

      def clear(options = nil)
        cascade(:clear, options)
      end

      def cleanup(options = nil)
        cascade(:cleanup, options)
      end

      protected

      def synchronize(&block) # :nodoc:
        @monitor.synchronize(&block)
      end

      def cascade(method, *args) # :nodoc:
        synchronize do
          @stores.map do |store|
            store.send(method, *args) rescue nil
          end
        end
      end

      def read_entry(key, options) # :nodoc:
        entry = nil
        if !!options[:last_store]
          entry = @stores.last.send(:read_entry, key, options)
        else
          synchronize do
            store_index = @stores.find_index do |store|
              entry = store.send(:read_entry, key, options) rescue nil
            end
            write_missing_entry(key, entry, options, store_index) if store_index
          end
        end
        entry
      end

      def write_entry(key, entry, options) # :nodoc:
        if !!options[:last_store]
          @stores.last.send(:write_entry, key, entry, options)
        else
          cascade(:write_entry, key, entry, options)
        end
        true
      end

      def delete_entry(key, options) # :nodoc:
        cascade(:delete_entry, key, options)
        true
      end

      private

      def write_missing_entry(key, entry, options, store_index)
        @stores[0...store_index].each do |store|
          store.send(:write_entry, key, entry, options)
        end
      end
    end
  end
end
