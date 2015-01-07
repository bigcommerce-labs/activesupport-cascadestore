require 'logger'
require 'abstract_unit'
require 'active_support/cache'
require 'active_support/cache'
require 'active_support/cache/mem_cache_store'
require 'memcached_store'

# Tests the base functionality that should be identical across all cache stores.
module CacheStoreBehavior
  def test_should_read_and_write_strings
    assert @cache.write('foo', 'bar')
    assert_equal 'bar', @cache.read('foo')
  end

  def test_should_overwrite
    @cache.write('foo', 'bar')
    @cache.write('foo', 'baz')
    assert_equal 'baz', @cache.read('foo')
  end

  def test_fetch_without_cache_miss
    @cache.write('foo', 'bar')
    @cache.expects(:write).never
    assert_equal 'bar', @cache.fetch('foo') { 'baz' }
  end

  def test_fetch_with_cache_miss
    @cache.expects(:write).with('foo', 'baz', @cache.options)
    assert_equal 'baz', @cache.fetch('foo') { 'baz' }
  end

  def test_fetch_with_forced_cache_miss
    @cache.write('foo', 'bar')
    @cache.expects(:read).never
    @cache.expects(:write).with('foo', 'bar', @cache.options.merge(:force => true))
    @cache.fetch('foo', :force => true) { 'bar' }
  end

  def test_fetch_with_cached_nil
    @cache.write('foo', nil)
    @cache.expects(:write).never
    assert_nil @cache.fetch('foo') { 'baz' }
  end

  def test_should_read_and_write_hash
    assert @cache.write('foo', {:a => "b"})
    assert_equal({:a => "b"}, @cache.read('foo'))
  end

  def test_should_read_and_write_integer
    assert @cache.write('foo', 1)
    assert_equal 1, @cache.read('foo')
  end

  def test_should_read_and_write_nil
    assert @cache.write('foo', nil)
    assert_equal nil, @cache.read('foo')
  end

  def test_should_read_and_write_false
    assert @cache.write('foo', false)
    assert_equal false, @cache.read('foo')
  end

  def test_read_multi
    @cache.write('foo', 'bar')
    @cache.write('fu', 'baz')
    @cache.write('fud', 'biz')
    assert_equal({"foo" => "bar", "fu" => "baz"}, @cache.read_multi('foo', 'fu'))
  end

  def test_read_multi_with_expires
    @cache.write('foo', 'bar', :expires_in => 0.001)
    @cache.write('fu', 'baz')
    @cache.write('fud', 'biz')
    sleep(0.002)
    assert_equal({"fu" => "baz"}, @cache.read_multi('foo', 'fu'))
  end

  def test_read_and_write_compressed_small_data
    @cache.write('foo', 'bar', :compress => true)
    value = @cache.send(:read_entry, 'foo', {}).value
    assert_equal 'bar', @cache.read('foo')
    assert_equal 'bar', value
  end

  def test_read_and_write_compressed_large_data
    @cache.write('foo', 'bar', :compress => true, :compress_threshold => 2)
    value = @cache.send(:read_entry, 'foo', {}).value
    assert_equal 'bar', @cache.read('foo')
    assert_equal 'bar', value
  end

  def test_read_and_write_compressed_nil
    @cache.write('foo', nil, :compress => true)
    assert_nil @cache.read('foo')
  end

  def test_cache_key
    obj = Object.new
    def obj.cache_key
      :foo
    end
    @cache.write(obj, "bar")
    assert_equal "bar", @cache.read("foo")
  end

  def test_param_as_cache_key
    obj = Object.new
    def obj.to_param
      "foo"
    end
    @cache.write(obj, "bar")
    assert_equal "bar", @cache.read("foo")
  end

  def test_array_as_cache_key
    @cache.write([:fu, "foo"], "bar")
    assert_equal "bar", @cache.read("fu/foo")
  end

  def test_hash_as_cache_key
    @cache.write({:foo => 1, :fu => 2}, "bar")
    assert_equal "bar", @cache.read("foo=1/fu=2")
  end

  def test_keys_are_case_sensitive
    @cache.write("foo", "bar")
    assert_nil @cache.read("FOO")
  end

  def test_exist
    @cache.write('foo', 'bar')
    assert @cache.exist?('foo')
    assert !@cache.exist?('bar')
  end

  def test_nil_exist
    @cache.write('foo', nil)
    assert @cache.exist?('foo')
  end

  def test_delete
    @cache.write('foo', 'bar')
    assert @cache.exist?('foo')
    assert @cache.delete('foo')
    assert !@cache.exist?('foo')
  end

  def test_original_store_objects_should_not_be_immutable
    bar = 'bar'
    @cache.write('foo', bar)
    assert_nothing_raised { bar.gsub!(/.*/, 'baz') }
  end

  def test_expires_in
    time = Time.local(2008, 4, 24)
    Time.stubs(:now).returns(time)

    @cache.write('foo', 'bar')
    assert_equal 'bar', @cache.read('foo')

    Time.stubs(:now).returns(time + 30)
    assert_equal 'bar', @cache.read('foo')

    Time.stubs(:now).returns(time + 61)
    assert_nil @cache.read('foo')
    Time.unstub(:now)
  end

  def test_race_condition_protection
    time = Time.now
    @cache.write('foo', 'bar', :expires_in => 60)
    Time.stubs(:now).returns(time + 61)
    result = @cache.fetch('foo', :race_condition_ttl => 10) do
      assert_equal 'bar', @cache.read('foo')
      "baz"
    end
    assert_equal "baz", result
    Time.unstub(:now)
  end

  def test_race_condition_protection_is_limited
    time = Time.now
    @cache.write('foo', 'bar', :expires_in => 60)
    Time.stubs(:now).returns(time + 71)
    result = @cache.fetch('foo', :race_condition_ttl => 10) do
      assert_equal nil, @cache.read('foo')
      "baz"
    end
    assert_equal "baz", result
    Time.unstub(:now)
  end

  def test_race_condition_protection_is_safe
    time = Time.now
    @cache.write('foo', 'bar', :expires_in => 60)
    Time.stubs(:now).returns(time + 61)
    begin
      @cache.fetch('foo', :race_condition_ttl => 10) do
        assert_equal 'bar', @cache.read('foo')
        raise ArgumentError.new
      end
    rescue ArgumentError
    end
    assert_equal "bar", @cache.read('foo')
    Time.stubs(:now).returns(time + 71)
    assert_nil @cache.read('foo')
    Time.unstub(:now)
  end

  def test_crazy_key_characters
    crazy_key = "#/:*(<+=> )&$%@?;'\"\'`~-"
    assert @cache.write(crazy_key, "1", :raw => true)
    assert_equal "1", @cache.read(crazy_key)
    assert_equal "1", @cache.fetch(crazy_key)
    assert @cache.delete(crazy_key)
    assert_equal "2", @cache.fetch(crazy_key, :raw => true) { "2" }
    assert_equal 3, @cache.increment(crazy_key)
    assert_equal 2, @cache.decrement(crazy_key)
  end

  def test_really_long_keys
    key = ""
    900.times{key << "x"}
    assert @cache.write(key, "bar")
    assert_equal "bar", @cache.read(key)
    assert_equal "bar", @cache.fetch(key)
    assert_nil @cache.read("#{key}x")
    assert_equal({key => "bar"}, @cache.read_multi(key))
    assert @cache.delete(key)
  end

  def test_missed_read_writes_to_higher_level_stores
    @store2.write('foo', 'bar')
    assert_equal 'bar', @store2.read('foo')
    assert_nil @store1.read('foo')
    assert_equal 'bar', @cache.read('foo')
    assert_equal 'bar', @store1.read('foo')
  end
end

# https://rails.lighthouseapp.com/projects/8994/tickets/6225-memcachestore-cant-deal-with-umlauts-and-special-characters
# The error is caused by charcter encodings that can't be compared with ASCII-8BIT regular expressions and by special
# characters like the umlaut in UTF-8.
module EncodedKeyCacheBehavior
  Encoding.list.each do |encoding|
    define_method "test_#{encoding.name.underscore}_encoded_values" do
      key = "foo".force_encoding(encoding)
      assert @cache.write(key, "1", :raw => true)
      assert_equal "1", @cache.read(key)
      assert_equal "1", @cache.fetch(key)
      assert @cache.delete(key)
      assert_equal "2", @cache.fetch(key, :raw => true) { "2" }
      assert_equal 3, @cache.increment(key)
      assert_equal 2, @cache.decrement(key)
    end
  end

  def test_common_utf8_values
    key = "\xC3\xBCmlaut".force_encoding(Encoding::UTF_8)
    assert @cache.write(key, "1", :raw => true)
    assert_equal "1", @cache.read(key)
    assert_equal "1", @cache.fetch(key)
    assert @cache.delete(key)
    assert_equal "2", @cache.fetch(key, :raw => true) { "2" }
    assert_equal 3, @cache.increment(key)
    assert_equal 2, @cache.decrement(key)
  end

  def test_retains_encoding
    key = "\xC3\xBCmlaut".force_encoding(Encoding::UTF_8)
    assert @cache.write(key, "1", :raw => true)
    assert_equal Encoding::UTF_8, key.encoding
  end
end

module CacheDeleteMatchedBehavior
  def test_delete_matched
    @cache.write("foo", "bar")
    @cache.write("fu", "baz")
    @cache.write("foo/bar", "baz")
    @cache.write("fu/baz", "bar")
    @cache.delete_matched(/oo/)
    assert !@cache.exist?("foo")
    assert @cache.exist?("fu")
    assert !@cache.exist?("foo/bar")
    assert @cache.exist?("fu/baz")
  end
end

module MultipleCacheBehaviour
  def test_default_child_store_options
    assert_equal @store1.options[:expires_in], 60
  end

  def test_empty_store_cache_miss
    cache = ActiveSupport::Cache.lookup_store(:cascade_store)
    assert cache.write('foo', 'bar')
    assert cache.fetch('foo').nil?
  end

  def test_cascade_write
    @cache.write('foo', 'bar')
    assert_equal @store1.read('foo'), 'bar'
    assert_equal @store2.read('foo'), 'bar'
  end

  def test_cascade_read_returns_first_hit
    @store1.write('foo', 'bar')
    @store2.expects(:read_entry).never
    assert_equal @cache.read('foo'), 'bar'
  end

  def test_cascade_read_fallback
    @store1.delete('foo')
    @store2.write('foo', 'bar')
    assert_equal @cache.read('foo'), 'bar'
  end

  def test_cascade_read_not_found
    assert_equal @cache.read('foo'), nil
  end

  def test_cascade_delete
    @store1.write('foo', 'bar')
    @store2.write('foo', 'bar')
    @cache.delete('foo')
    assert_equal @store1.read('foo'), nil
    assert_equal @store2.read('foo'), nil
  end

  def test_write_last_store
    @cache.write('foo', 'bar', last_store: true)
    assert_equal @store1.read('foo'), nil
    assert_equal @store2.read('foo'), 'bar'
  end

  def test_read_last_store
    @store1.write('foo', 'bar')
    @store2.write('foo', 'bar')
    @store1.expects(:read_entry).never
    assert_equal @cache.read('foo', last_store: true), 'bar'
  end

  def test_fetch_last_store
    @store1.expects(:read_entry).never
    @store1.expects(:write_entry).never
    assert_equal 'baz', @cache.fetch('foo', last_store: true) { 'baz' }
    assert_equal @store2.read('foo'), 'baz'
  end

  def test_clear
    @cache.write('foo', 'bar')
    @cache.clear
    assert_equal @store1.read('foo'), nil
    assert_equal @store2.read('foo'), nil
  end

end

module CacheIncrementDecrementBehavior
  def test_increment
    @cache.write('foo', 1, :raw => true)
    assert_equal 1, @cache.read('foo').to_i
    assert_equal 2, @cache.increment('foo')
    assert_equal 2, @cache.read('foo').to_i
    assert_equal 3, @cache.increment('foo')
    assert_equal 3, @cache.read('foo').to_i
  end

  def test_decrement
    @cache.write('foo', 3, :raw => true)
    assert_equal 3, @cache.read('foo').to_i
    assert_equal 2, @cache.decrement('foo')
    assert_equal 2, @cache.read('foo').to_i
    assert_equal 1, @cache.decrement('foo')
    assert_equal 1, @cache.read('foo').to_i
  end
end

class MemoryStoresTest < ActiveSupport::TestCase
  def setup
    @cache = ActiveSupport::Cache.lookup_store(:cascade_store, {
      :expires_in => 60,
      :stores => [
        :memory_store,
        [:memory_store, :expires_in => 60]
      ]
    })
    @store1 = @cache.stores[0]
    @store2 = @cache.stores[1]
  end

  include CacheStoreBehavior
  include CacheIncrementDecrementBehavior
  include CacheDeleteMatchedBehavior
  include EncodedKeyCacheBehavior
  include MultipleCacheBehaviour

  def test_cleanup
    time = Time.now
    @cache.write('foo', 'bar', expires_in: 30)
    Time.stubs(:now).returns(time + 31)
    @cache.cleanup
    assert_equal @store1.read('foo'), nil
    assert_equal @store2.read('foo'), nil
    Time.unstub(:now)
  end

  def test_cascade_increment_partial_returns_num
    @store2.write('foo', 0)
    assert_equal @cache.increment('foo', 1), 1
    assert_equal @cache.read('foo'), 1
  end

  def test_cascade_decrement_partial_returns_num
    @store2.write('foo', 1)
    assert_equal @cache.decrement('foo', 1), 0
    assert_equal @cache.read('foo'), 0
  end
end

class MemoryMemcachedStoresTest < ActiveSupport::TestCase
  def setup
    @cache = ActiveSupport::Cache.lookup_store(:cascade_store, {
      :expires_in => 60,
      :stores => [
        :memory_store,
        [:memcached_store, :expires_in => 60]
      ]
    })
    @store1 = @cache.stores[0]
    @store2 = @cache.stores[1]
    @cache.clear
  end

  include CacheStoreBehavior
  include CacheIncrementDecrementBehavior
  include EncodedKeyCacheBehavior
  include MultipleCacheBehaviour
end
