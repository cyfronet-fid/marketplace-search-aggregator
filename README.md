# README

## Marketplace Search Aggregator

A lightweight Rails API for aggregating search results from multiple Marketplace nodes into a single, unified response. It fetches data in parallel, merges results, facets, and metadata, applies sorting, and supports pagination.

Key features:

- Fetch and aggregate results from a configurable list of nodes
- Parallel requests with graceful error handling and metadata about successes/failures
- Facets merging and result sorting (by score or reasonable defaults)
- Simple pagination (page, per_page)
- Node registry integration with fallback to a local static configuration
- In‑memory/durable caching via Rails cache (Solid Cache in production)

## Table of contents

- Overview and API
- Running locally (without Docker)
- Running with Docker
- Database setup
- Environment variables
- Development tips
- Tests

## Overview and API

This service queries a set of remote Marketplaces and merges their responses into one. The node list is resolved via a registry API or a static YAML file.

Exposed endpoints:

- GET /api/v1/health — health check; returns `OK`.
- GET /api/v1/services — aggregated search endpoint.
  * Query parameters:
    - page (integer, default: 1)
    - per_page (integer, default: 10)
    - nodes[] (optional, repeatable): limit aggregation to a subset of nodes by their `name`.
    - Any other query params are forwarded to the underlying nodes (except pagination params) and may influence their search.
  * Response:
    - results/offers: merged array of items (depending on the nodes’ payload structure)
    - facets: merged facet groups
    - pagination: total_count, total_pages, current_page, per_page, has_next_page, has_prev_page
    - metadata: aggregated_at, total_sources, successful_sources, failed_sources, nodes
    - highlights (if provided by nodes)

Note: When the registry is unavailable or disabled, the service falls back to config/default_endpoints.yml.

## Prerequisites

- Ruby 3.3.6
- Bundler
- SQLite 3 (used for primary, cache, and queue databases)
- Node.js is not required (API-only)

## Running locally (without Docker)

1) Clone the repository and install gems:

- bundle install

2) Configure environment (optional but recommended):

- Copy `.env` to your shell environment or export variables as needed (see “Environment variables” below).

3) Prepare the databases and start the server:

- `bin/setup`
- or run manually:
  * `bin/rails db:prepare`
  * `bin/dev` (uses Foreman and starts Rails on PORT, default 3015)
  * Alternatively: `PORT=3015 bin/rails s`

The API will be available at http://localhost:3015 (or the port you set).

## Running with Docker

Build the image:

```shell
docker build -t marketplace_search_aggregator .
```

Run the container (map host port to container’s port; default app port is 3000 inside Rails unless PORT is provided):

```shell
  docker run -d \
  -p 3015:3015 \
  --env-file .env \
  -e RAILS_ENV=production \
  -e RAILS_MASTER_KEY=<your_master_key_if_used> \
  --name marketplace_search_aggregator \
  marketplace_search_aggregator
```

Notes:

- The Dockerfile exposes 3015 and the default scripts respect PORT (from .env PORT=3015). You can change mapping, e.g. `-p 8080:3015` to access it on http://localhost:8080.
- The entrypoint runs `rails db:prepare` automatically when starting the server.
- SQLite database files are stored in /rails/db inside the container. A Docker volume is declared for persistence across restarts.

## Database setup

This app uses SQLite with three separate databases (primary, queue, cache) configured in config/database.yml. Common tasks:

- Create/migrate databases: bin/rails db:prepare
- Reset local data (careful!): bin/rails db:drop db:create db:migrate

In Docker, databases are prepared automatically at container start via the entrypoint.

## Environment variables

Application configuration (used by services):

- NODE_REGISTRY_URL — URL of the node registry service that returns available providers/nodes.
- NODE_REGISTRY_API_KEY — optional API key sent as X-Api-Key to the registry and node endpoints.
- STATIC_CONFIG — when set to 1/true/on/yes, disables registry calls and uses the static YAML file.
- STATIC_CONFIG_FILE — path to the static endpoints YAML. Default: config/default_endpoints.yml. The YAML can define `default`, or per‑environment lists. Each item should include at least `url` and optionally `name`, `pid`.

Runtime and Rails environment:

- PORT — web server port. Defaults to 3015 via bin/dev and .env. Docker also uses this by default.
- RAILS_ENV — environment (development, test, production). Defaults to development locally.
- RAILS_MAX_THREADS — Puma/ActiveRecord thread pool size. Default 5 (see config/database.yml).
- RAILS_LOG_LEVEL — production log level (default info).
- SECRET_KEY_BASE — in production you can provide it directly; otherwise Rails will use credentials (RAILS_MASTER_KEY).
- RAILS_MASTER_KEY — provides access to encrypted credentials; alternative to SECRET_KEY_BASE.

## Default/static endpoints

See config/default_endpoints.yml for an example. Example structure:

```yaml
default:
  - name: "CESSDA"
    pid: "21.T15999/CESSDA"
    url: "https://example.org/"
```

## Development tips

- Use bin/dev to start the server with Foreman, which respects PORT (defaults to 3015).
- Health check at /api/v1/health returns OK and is useful for readiness probes.

## Tests

Run the test suite:

- bin/rails test

Optional: run a single test file:

- bin/rails test test/models/some_test.rb

## Troubleshooting

- No endpoints returned: ensure NODE_REGISTRY_URL is reachable and/or set STATIC_CONFIG=1 to use config/default_endpoints.yml.
- CORS/API access from browsers: this service is API‑only; configure your proxy or add Rack CORS if needed.
- Ports don’t match: verify PORT in your environment and the host mapping you use with Docker (`-p host:container`).
