source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.6"

gem "rails", "~> 7.2.2.1"
gem "sqlite3", "~> 2.7"
gem "puma"
gem "bootsnap", ">= 1.4.4", require: false
gem "rack-cors"

# HTTP client for API calls
gem "faraday"
gem "faraday-net_http"

# JSON processing
gem "oj"

# Background jobs (optional)
gem "sidekiq"

group :development, :test do
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "dotenv-rails"
end

group :development do
  gem "listen", "~> 3.3"
  gem "spring"
  gem "prettier", require: false
end