require 'mysql2'
require 'concurrent/atomics'

# Instrument SQL time
class Mysql2::Client
  class << self
    attr_accessor :query_time, :query_count
  end
  self.query_count = Concurrent::AtomicReference.new(0)
  self.query_time = Concurrent::AtomicReference.new(0)

  if Gem::Version.new(Rails.version) >= Gem::Version.new('5.1.0')
    module QueryWithTiming
      def query(*args)
        start = Time.now
        super(*args)
      ensure
        duration = (Time.now - start)
        Mysql2::Client.query_time.update { |value| value + duration }
        Mysql2::Client.query_count.update { |value| value + 1 }
      end
    end

    Mysql2::Client.prepend(QueryWithTiming)
  else
    def query_with_timing(*args)
      start = Time.now
      query_without_timing(*args)
    ensure
      duration = (Time.now - start)
      Mysql2::Client.query_time.update { |value| value + duration }
      Mysql2::Client.query_count.update { |value| value + 1 }
    end

    alias_method_chain :query, :timing
  end
end

module Peek
  module Views
    class Mysql2 < View
      def duration
        ::Mysql2::Client.query_time.value
      end

      def formatted_duration
        ms = duration * 1000
        if ms >= 1000
          "%.2fms" % ms
        else
          "%.0fms" % ms
        end
      end

      def calls
        ::Mysql2::Client.query_count.value
      end

      def results
        { :duration => formatted_duration, :calls => calls }
      end

      private

      def setup_subscribers
        # Reset each counter when a new request starts
        before_request do
          ::Mysql2::Client.query_time.value = 0
          ::Mysql2::Client.query_count.value = 0
        end
      end
    end
  end
end
