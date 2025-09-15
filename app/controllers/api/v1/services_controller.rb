# frozen_string_literal: true

class Api::V1::ServicesController < ApplicationController
  before_action :set_endpoints, only: [:index]

  def index
    aggregator = DataAggregatorService.new(@endpoints, params)
    result = aggregator.aggregate_data
    result["nodes"] = @default_endpoints
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
    @default_endpoints = [
      { name: "CESSDA", url: "http://localhost:5000/api/v1/search/services" },
      { name: "NI4OS", url: "http://marketplace-2.docker-fid.grid.cyf-kr.edu.pl/api/v1/search/services" }
    ]
    return @endpoints = @default_endpoints unless params[:nodes].present?
    if params[:nodes].present?
      @endpoints = @default_endpoints.select { |endpoint| params[:nodes].include?(endpoint[:name]) }
    end
  end
end
