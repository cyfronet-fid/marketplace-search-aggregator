# frozen_string_literal: true

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.6"

gem "rails", "~> 8.1.0"
gem "sqlite3", "~> 1.4"
gem "puma"
gem "bootsnap", ">= 1.4.4", require: false
gem "rack-cors"
gem "solid_cache"
gem "solid_queue"

# HTTP client for API calls
gem "faraday"
gem "faraday-net_http"
# Follow HTTP redirects for Faraday v2
gem "faraday-follow_redirects"

# JSON processing
gem "oj"

group :development, :test do
  gem "byebug", platforms: [:mri, :windows]
  gem "factory_bot_rails"
  gem "dotenv-rails"
  gem "rubocop"
  gem "brakeman"
  gem "prettier", require: false
  gem "overcommit", require: false
  gem "rubocop-rails"
end

group :development do
  gem "listen", "~> 3.3"
  gem "spring"
end
gem "solid_cable", "~> 3.0"
