module IdentityCache
  module MarshalCodec
    def self.encode(value)
      Marshal.dump(value)
    end

    def self.decode(data)
      Marshal.load(data)
    end
  end
end
