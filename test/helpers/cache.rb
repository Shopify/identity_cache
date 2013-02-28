module Rails
  class Cache

    def initialize
      @cache = {}
    end

    def fetch(e)
      if @cache.key?(e)
        return read(e)
      else
        a = yield
        write(e,a)
        return a
      end
    end

    def clear
      @cache.clear
    end

    def write(a,b)
      @cache[a] = b
    end

    def delete(a)
      @cache.delete(a)
    end

    def read(a)
      @cache[a]
    end

    def read_multi(*keys)
      keys.reduce({}) do |hash, key|
        hash[key] = @cache[key]
        hash
      end
    end
  end

  def self.cache
    @@cache ||= Cache.new
  end

  class Logger
    def info(string)
    end
    def debug(string)
    end
  end

  def self.logger
    @logger = Logger.new
  end
end
