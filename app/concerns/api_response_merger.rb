module ApiResponseMerger
  extend ActiveSupport::Concern

  def merge_api_responses(*responses)
    responses
      .compact
      .reduce(base_structure) do |merged, response|
        parsed = parse_json_response(response)

        %w[results offers facets pagination].each do |key|
          merged[key] ||= []
          merged[key].concat(Array(parsed[key])) if parsed[key]
        end

        merged
      end
  end

  private

  def parse_json_response(response)
    return response if response.is_a?(Hash)

    JSON.parse(response.to_s)
  rescue JSON::ParserError
    {}
  end

  def base_structure
    { "results" => [], "offers" => [], "facets" => [], "pagination" => [] }
  end
end
