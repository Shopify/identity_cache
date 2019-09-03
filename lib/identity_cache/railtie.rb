module IdentityCache
  class Railtie < Rails::Railtie
    initializer "identity_cache.setup" do |app|
      app.config.eager_load_namespaces << IdentityCache
    end
  end
end
