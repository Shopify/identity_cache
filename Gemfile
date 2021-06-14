# frozen_string_literal: true
source "https://rubygems.org"
gemspec

# Skip rubocop 1.16.1 until the next release which will include the fix:
# https://github.com/rubocop/rubocop/pull/9862
gem "rubocop", "~> 1.5", "!= 1.16.1"

gem "rubocop-shopify", "~> 2.0.1", require: false

gem "mysql2", "~> 0.5.3", platform: :mri
gem "pg", ">= 0.18", "< 2.0", platform: :mri
gem "memcached", "~> 1.8.0", platform: :mri
gem "memcached_store", "~> 1.0.0", platform: :mri
gem "dalli", "~> 2.7.11"
gem "cityhash", "~> 0.6.0", platform: :mri

gem "byebug", platform: :mri
gem "stackprof", platform: :mri
