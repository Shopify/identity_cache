module IdentityCache
  module ActiveRecordExtension
    def inherited(base)
      ret = super if defined? super
      ConfigurationDSL.install_parent_expiry_hooks(base)
      ret
    end
  end
  ActiveRecord::Base.extend(ActiveRecordExtension)
end
