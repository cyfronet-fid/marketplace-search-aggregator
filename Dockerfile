# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t marketplace_search_aggregator .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name marketplace_search_aggregator marketplace_search_aggregator

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages (include SQLite runtime)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips libsqlite3-0 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems (SQLite dev headers)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libsqlite3-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Ensure database directory and production SQLite file exist in the image so a Docker volume can be initialized with proper ownership
RUN mkdir -p db && \
    touch db/production.sqlite3 && \
    touch db/production-cache.sqlite3 && \
    touch db/production-queue.sqlite3 && \
    touch db/production-cable.sqlite3

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/




# Final stage for app image
FROM base

# At runtime, provide credentials or SECRET_KEY_BASE via environment if needed.
# Preferred: supply RAILS_MASTER_KEY (or mount config/master.key) so Rails derives secret_key_base from credentials.
# Example runtime usage:
#   docker run --env-file .env -p 80:80 --name marketplace_search_aggregator marketplace_search_aggregator

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp config

# Declare db as a volume so that db/production.sqlite3 persists between container restarts
VOLUME ["/rails/db"]

USER 1000:1000

# Entrypoint prepares the database and sets secrets if needed
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server directly with Rails (Puma)
EXPOSE 3015
CMD ["./bin/rails", "server"]
