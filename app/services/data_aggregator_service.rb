class DataAggregatorService
  include ApiResponseMerger

  def initialize(endpoints = [], params = {})
    @endpoints = endpoints
    @params = params
    @cached_data = nil
    @http_client =
      Faraday.new do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.adapter Faraday.default_adapter
      end
  end

  def aggregate_data
    @cached_data ||= fetch_and_merge_all_data

    paginate_data(@cached_data)
  end

  private

  def fetch_and_merge_all_data
    responses = fetch_all_endpoints
    puts responses.map { |r| [r[:data]["pagination"], r[:source]] }
    merged_data = merge_api_responses(*responses)
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
            api_params = @params.except(:page, "page", :per_page, "per_page").merge(per_page: 10000)
            response = @http_client.get(endpoint[:url], api_params)
            { source: endpoint[:name], data: response.body, status: response.status, success: response.success? }
          rescue StandardError => e
            { source: endpoint[:name], data: nil, error: e.message, success: false }
          end
        end
      end

    threads.map(&:value)
  end

  def merge_responses(responses)
    successful_responses = responses.select { |r| r[:success] }

    merged_data = {
      sources: successful_responses.map { |r| r[:source] },
      data: [],
      metadata: {
        total_sources: @endpoints.count,
        successful_sources: successful_responses.count,
        failed_sources: responses.count - successful_responses.count,
        aggregated_at: Time.current.iso8601
      }
    }

    successful_responses.each do |response|
      case response[:data]
      when Array
        merged_data[:data].concat(response[:data])
      when Hash
        merged_data[:data] << response[:data]
      else
        merged_data[:data] << { source: response[:source], content: response[:data] }
      end
    end

    merged_data
  end

  def sort_data(merged_data)
    main_results = merged_data["results"] || merged_data["offers"]
    
    if main_results.is_a?(Array) && main_results.first.is_a?(Hash)
      sort_key = determine_sort_key(main_results.first)
      sorted_results = main_results.sort_by do |item|
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
end
