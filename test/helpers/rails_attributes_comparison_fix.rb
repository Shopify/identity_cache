if defined?(ActiveRecord::AttributeSet)
  if ActiveRecord::AttributeSet.instance_method(:==).owner == BasicObject
    class ActiveRecord::AttributeSet
      def ==(other)
        attributes == other.attributes
      end
    end

    class ActiveRecord::LazyAttributeHash
      def ==(other)
        if other.is_a?(ActiveRecord::LazyAttributeHash)
          materialize == other.send(:materialize)
        else
          materialize == other
        end
      end
    end
  else
    raise "This bug has been fixed upstream, and this (test only) monkey patch can be removed"
  end
end
