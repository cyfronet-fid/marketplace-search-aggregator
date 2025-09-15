source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.6"

gem "rails", "~> 7.2.2.1"
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

# Background jobs (optional)
gem "sidekiq"

group :development, :test do
  gem "byebug", platforms: [:mri, :windows]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "dotenv-rails"
end

group :development do
  gem "listen", "~> 3.3"
  gem "spring"
  gem "prettier", require: false
end