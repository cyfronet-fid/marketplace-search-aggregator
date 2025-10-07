# frozen_string_literal: true

require "digest"
require "json"
require "faraday"
require "faraday/follow_redirects"

class DataAggregatorService
  include ApiResponseMerger

  def initialize(endpoints = [], params = {})
    @endpoints = endpoints
    @params = params.compact_blank
    @cached_data = nil
    @http_client =
      Faraday.new do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.use Faraday::FollowRedirects::Middleware
        faraday.adapter Faraday.default_adapter
      end
  end

  def aggregate_data
    data = cached_all_data
    paginate_data(data)
  end

  private

  def cached_all_data
    Rails.cache.fetch(cache_key) { fetch_and_merge_all_data }
  end

  def cache_key
    endpoints_norm =
      @endpoints
        .map do |e|
          if e.is_a?(Hash)
            name = (e[:name] || e["name"] || e[:url] || e["url"]).to_s
            url = (e[:url] || e["url"] || e[:name] || e["name"] || name).to_s
            { name: name, url: url }
          else
            s = e.to_s
            { name: s, url: s }
          end
        end
        .sort_by { |h| [h[:name], h[:url]] }
    raw_params =
      if @params.respond_to?(:to_unsafe_h)
        @params.to_unsafe_h
      elsif @params.respond_to?(:to_h)
        @params.to_h
      else
        @params
      end
    query_params = (raw_params || {}).except(:page, "page", :per_page, "per_page")
    query_params = query_params.transform_keys(&:to_s)
    query_params_sorted = query_params.keys.sort.each_with_object({}) { |k, acc| acc[k] = query_params[k] }
    payload = { endpoints: endpoints_norm, params: query_params_sorted }
    version = "v1"
    "data_aggregator:#{version}:#{Digest::SHA256.hexdigest(JSON.generate(payload))}"
  end

  def fetch_and_merge_all_data
    responses = fetch_all_endpoints

    merged_data = merge_api_responses(*responses)

    merged_data["metadata"] = merged_data["metadata"].merge(metadata(responses))
    sort_data(merged_data)
  end

  def paginate_data(all_data)
    page = (@params[:page] || @params["page"] || 1).to_i
    per_page = (@params[:per_page] || @params["per_page"] || 10).to_i

    main_results = all_data["results"] || all_data["offers"] || []
    total_count = main_results.length

    offset = (page - 1) * per_page
    paginated_results = main_results[offset, per_page] || []

    paginated_data = all_data.dup

    if all_data["results"]
      paginated_data["results"] = paginated_results
    elsif all_data["offers"]
      paginated_data["offers"] = paginated_results
    end

    paginated_data["pagination"] = {
      "current_page" => page,
      "per_page" => per_page,
      "total_count" => total_count,
      "total_pages" => (total_count.to_f / per_page).ceil,
      "has_next_page" => page < (total_count.to_f / per_page).ceil,
      "has_prev_page" => page > 1
    }

    paginated_data
  end

  def fetch_all_endpoints
    threads =
      @endpoints.map do |endpoint|
        Thread.new do
          begin
            api_params = @params.except(:page, "page", :per_page, "per_page").merge(per_page: 10_000)
            url = endpoint.is_a?(Hash) ? (endpoint[:url] || endpoint["url"]).to_s : endpoint.to_s
            name = endpoint.is_a?(Hash) ? ((endpoint[:name] || endpoint["name"]) || url).to_s : url
            response = @http_client.get(url, api_params)
            { source: name, url: url, data: response.body, status: response.status, success: response.success? }
          rescue StandardError => e
            url = endpoint.is_a?(Hash) ? (endpoint[:url] || endpoint["url"]).to_s : endpoint.to_s
            name = endpoint.is_a?(Hash) ? ((endpoint[:name] || endpoint["name"]) || url).to_s : url
            { source: name, url: url, data: nil, error: e.message, success: false }
          end
        end
      end

    threads.map(&:value)
  end

  def sort_data(merged_data)
    main_results = merged_data["results"] || merged_data["offers"]

    if main_results.is_a?(Array) && main_results.first.is_a?(Hash)
      sort_key = determine_sort_key(main_results.first)
      sorted_results =
        main_results.sort_by do |item|
          value = item[sort_key] || item[sort_key.to_s] || 0
          -value.to_f
        end

      if merged_data["results"]
        merged_data["results"] = sorted_results
      elsif merged_data["offers"]
        merged_data["offers"] = sorted_results
      end
    end

    merged_data
  end

  def determine_sort_key(sample_item)
    return :score if sample_item.key?(:score) || sample_item.key?("score")

    priority_keys = %i[created_at timestamp updated_at id date]

    priority_keys.each { |key| return key if sample_item.key?(key) || sample_item.key?(key.to_s) }

    sample_item.keys.first
  end

  def metadata(responses)
    successful_responses = responses.select { |response| response[:success] }
    requests = @endpoints.size
    {
      "total_sources" => requests,
      "successful_sources" => successful_responses.count,
      "failed_sources" => requests - successful_responses.count,
      "aggregated_at" => Time.current.iso8601
    }
  end
end
