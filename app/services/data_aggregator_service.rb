class DataAggregatorService
  include ApiResponseMerger

  def initialize(endpoints = [])
    @endpoints = endpoints
    @http_client =
      Faraday.new do |faraday|
        faraday.request :json
        faraday.response :json
        faraday.adapter Faraday.default_adapter
      end
  end

  def aggregate_data
    responses = fetch_all_endpoints
    puts responses.map { |r| [r[:data]["pagination"], r[:source]] }
    merged_data = merge_api_responses(responses)
    sort_data(merged_data)
  end

  private

  def fetch_all_endpoints
    threads =
      @endpoints.map do |endpoint|
        Thread.new do
          begin
            response = @http_client.get(endpoint[:url])
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
    puts merged_data
    if merged_data[:data].is_a?(Array) && merged_data[:data].first.is_a?(Hash)
      sort_key = determine_sort_key(merged_data[:data].first)
      merged_data[:data] = merged_data[:data].sort_by do |item|
        value = item[sort_key] || item[sort_key.to_s] || 0
        -value.to_f
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
