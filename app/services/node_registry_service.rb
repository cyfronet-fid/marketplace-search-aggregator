# frozen_string_literal: true

require "yaml"
require "faraday"
require "faraday/follow_redirects"

# Service responsible for providing the list of registry endpoints.
# Default behavior: fetch from NODE_REGISTRY_URL and cache the result.
# Fallback (rescue): load from config/default_endpoints.yml
class NodeRegistryService
  CACHE_KEY = "node_registry:endpoints:v1"
  DEFAULT_CACHE_TTL = 10.minutes

  def initialize(cache_ttl: DEFAULT_CACHE_TTL)
    @cache_ttl = cache_ttl
    @api_key = ENV["NODE_REGISTRY_API_KEY"].to_s.strip
    @static_config = truthy_env?("STATIC_CONFIG")
    @http_client =
      Faraday.new do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.use Faraday::FollowRedirects::Middleware
        faraday.adapter Faraday.default_adapter
        faraday.options.timeout = 5
        faraday.options.open_timeout = 3
      end
  end

  # Returns endpoints array with items like {"name"=>..., "url"=>..., "pid"=>...}
  # or symbolized keys. The controller/consumers should accept either.
  def endpoints
    if @static_config
      Rails.logger.info("NodeRegistryService: STATIC_CONFIG enabled, using default endpoints")
      return default_endpoints
    end

    Rails.cache.fetch(CACHE_KEY, expires_in: @cache_ttl) { fetch_from_registry }
  rescue StandardError => e
    Rails.logger.warn("NodeRegistryService: cache/fetch error: #{e.class}: #{e.message}")
    default_endpoints
  end

  def default_endpoints
    load_default_endpoints
  rescue StandardError => e
    Rails.logger.error("NodeRegistryService: failed to load default_endpoints.yml: #{e.class}: #{e.message}")
    []
  end

  private

  def truthy_env?(name)
    v = ENV[name].to_s.strip.downcase
    %w[1 true yes on y].include?(v)
  end

  def fetch_from_registry
    url = ENV.fetch("NODE_REGISTRY_URL", nil)
    raise "NODE_REGISTRY_URL not set" if url.blank?

    response = @http_client.get(url) { |req| apply_api_key(req) }

    raise "Registry request failed with status #{response.status}" unless response.success?

    body = response.body

    # If the registry returns providers with node_endpoint, perform nested fetching
    if body.is_a?(Array) && body.any? && body.first.is_a?(Hash) &&
         (body.first.key?("node_endpoint") || body.first.key?(:node_endpoint))
      build_endpoints_from_registry(body)
    else
      normalize_endpoints(body)
    end
  rescue StandardError => e
    Rails.logger.warn("NodeRegistryService: fetch_from_registry failed: #{e.class}: #{e.message}")
    # Fallback to defaults on any error
    default_endpoints
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def build_endpoints_from_registry(providers)
    providers = Array(providers)

    threads =
      providers.map do |item|
        Thread.new do
          name = item["name"] || item[:name] || item["id"] || item[:id]
          pid = item["pid"] || item[:pid]
          node_ep = item["node_endpoint"] || item[:node_endpoint]

          raise "Missing node_endpoint for #{name || pid || "provider"}" if node_ep.to_s.strip.empty?

          resp = @http_client.get(node_ep) { |req| apply_api_key(req) }
          raise "node_endpoint request failed with status #{resp.status}" unless resp.success?

          data = resp.body || {}
          caps = data["capabilities"] || data[:capabilities] || []
          front =
            Array(caps).find do |c|
              (c["capability_type"] || c[:capability_type]).to_s.strip.casecmp("Front Office").zero?
            end

          url = front && (front["endpoint"] || front[:endpoint])

          # if endpoint is "-", treat as missing
          url = nil if url.to_s.strip == "-"

          raise "Front Office endpoint not found for #{name || pid || node_ep}" if url.to_s.strip.empty?

          { name: (name || url).to_s, pid: pid.to_s, url: url.to_s }
        rescue StandardError => e
          Rails.logger.warn("NodeRegistryService: provider processing failed: #{e.class}: #{e.message}")
          nil
        end
      end

    results = threads.map(&:value).compact
    # Ensure we only return entries with non-blank URL
    results.reject { |h| h[:url].to_s.strip.empty? }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def load_default_endpoints
    path = ENV.fetch("STATIC_CONFIG_FILE", Rails.root.join("config", "default_endpoints.yml"))
    raise "Default endpoints file not found at #{path}" unless File.exist?(path)

    raw = YAML.safe_load_file(File.read(path), aliases: true)

    list =
      case raw
      when Array
        raw
      when Hash
        env = Rails.env.to_s
        raw[env] || raw[env.to_sym] || raw["default"] || raw[:default] || []
      else
        []
      end

    normalize_endpoints(list)
  end

  # Normalize the list to array of hashes with name, url, and pid (if available)
  def normalize_endpoints(list)
    Array(list)
      .map do |item|
        if item.is_a?(Hash)
          name = item["name"] || item[:name] || item["service"] || item[:service] || item["id"] || item[:id]
          url = item["url"] || item[:url]
          pid = item["pid"] || item[:pid]
          { name: (name || url).to_s, url: url.to_s, pid: pid&.to_s }
        else
          s = item.to_s
          { name: s, url: s }
        end
      end
      .reject { |h| h[:url].blank? }
  end

  def apply_api_key(req)
    return if @api_key.empty?

    req.headers["X-Api-Key"] = @api_key
  end
end
