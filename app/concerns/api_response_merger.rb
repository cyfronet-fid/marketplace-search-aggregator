# frozen_string_literal: true

module ApiResponseMerger
  extend ActiveSupport::Concern

  def merge_api_responses(*responses)
    responses
      .compact
      .reduce(base_structure) do |merged, response|
        parsed = parse_json_response(response)
        data = parsed[:data] || parsed["data"] || {}

        Rails.logger.debug "Merge data from #{parsed[:url]}. Response status #{parsed[:status]}"

        if data.is_a?(Array)
          merged["results"] ||= []
          merged["results"].concat(data)
        else
          %w[results offers].each do |key|
            merged[key] ||= []
            if data.is_a?(Hash) && (data[key] || data[key&.to_sym])
              merged[key].concat(Array(data[key] || data[key&.to_sym]))
            end
          end
        end
        # Merge facets from parsed[:facets] / parsed["facets"] or nested in data[:facets] / data["facets"]
        new_facets = nil
        new_facets = data[:facets] || data["facets"] if data.is_a?(Hash)
        new_facets ||= parsed[:facets] || parsed["facets"]
        merge_facets!(merged["facets"], new_facets) if new_facets.is_a?(Hash)

        # Pagination and highlights
        if data.is_a?(Hash)
          pagination = data[:pagination] || data["pagination"]
          merged["pagination"] = pagination if pagination

          highlights = data["highlights"] || data[:highlights]
          merged["highlights"].merge!(highlights) if highlights.is_a?(Hash)
        end

        # Metadata
        merged["metadata"]["nodes"] << {
          "name" => parsed[:source],
          "url" => parsed[:url],
          "status" => parsed[:status],
          "success" => parsed[:success]
        }

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

  def merge_facets!(accumulator, new_facets)
    return accumulator unless new_facets

    new_facets.each do |group_key, items|
      group = group_key.to_s
      accumulator[group] ||= []
      next unless items.is_a?(Array)

      items.each do |item|
        if item.is_a?(Hash)
          eid = (item["eid"] || item[:eid])
          name = (item["name"] || item[:name])
          count = (item["count"] || item[:count] || 0).to_i
          children = (item["children"] || item[:children]) || []
        else
          eid = nil
        end
        next unless eid

        existing = accumulator[group].find { |i| (i["eid"] || i[:eid]) == eid }
        if existing
          existing_count = (existing["count"] || existing[:count] || 0).to_i
          # Normalize to string keys in the accumulator
          existing["count"] = existing_count + count
          existing["name"] = existing["name"] || existing[:name] || name
          existing["eid"] = existing["eid"] || existing[:eid] || eid
          # Preserve existing children if present; otherwise adopt incoming children
          existing_children = (existing["children"] || existing[:children] || [])
          incoming_children = children.is_a?(Array) ? children : []
          existing["children"] = existing_children.any? ? existing_children : incoming_children
        else
          accumulator[group] << { "name" => name, "eid" => eid, "count" => count, "children" => children }
        end
      end

      # Sort the group facets by count descending as required
      accumulator[group].sort_by! { |i| -((i["count"] || i[:count] || 0).to_i) }
    end

    accumulator
  end

  def base_structure
    {
      "results" => [],
      "offers" => [],
      "facets" => {
      },
      "pagination" => {
      },
      "metadata" => {
        "nodes" => []
      },
      "highlights" => {
      }
    }
  end
end
