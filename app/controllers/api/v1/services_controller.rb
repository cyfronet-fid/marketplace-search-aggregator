# frozen_string_literal: true

class Api::V1::ServicesController < ApplicationController
  before_action :set_endpoints, only: [:index]

  def index
    aggregator = DataAggregatorService.new(@endpoints, params)
    result = aggregator.aggregate_data
    result["nodes"] = @all_nodes
    render json: { status: "success" }.merge(result)
  rescue StandardError => e
    puts e
    render json: { status: "error", message: e.message }, status: :internal_server_error
  end

  def custom_aggregate
    custom_endpoints = params[:endpoints]&.map(&:permit!)&.map(&:to_h)

    if custom_endpoints.blank?
      render json: { error: "No endpoints provided" }, status: :bad_request
      return
    end

    aggregator = DataAggregatorService.new(custom_endpoints)
    result = aggregator.aggregate_data

    render json: { status: "success", result: result }
  rescue StandardError => e
    render json: { status: "error", message: e.message }, status: :internal_server_error
  end

  private

  def set_endpoints
    registry = NodeRegistryService.new
    @all_nodes = registry.endpoints
    # fallback already handled inside service, but keep a minimal guard
    @all_nodes = registry.default_endpoints if @all_nodes.blank?

    if params[:nodes].present?
      names = Array(params[:nodes])
      @endpoints =
        @all_nodes.select do |endpoint|
          name = endpoint[:name] || endpoint["name"]
          names.include?(name)
        end
    else
      @endpoints = @all_nodes
    end
  end
end
