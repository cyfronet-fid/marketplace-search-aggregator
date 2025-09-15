# frozen_string_literal: true

require 'test_helper'

class DummyMerger
  include ApiResponseMerger
end

class ApiResponseMergerTest < ActiveSupport::TestCase
  test 'merges facets by eid and sums counts from data.facets and top-level parsed facets' do
    merger = DummyMerger.new

    response_a = {
      source: 'node_a',
      url: 'http://example.com/a',
      status: 200,
      success: true,
      data: {
        'results' => [],
        'facets' => {
          categories: [
            { 'name' => 'Category 1', 'eid' => 'category-cat1', 'count' => 2 },
            { 'name' => 'Category 2', 'eid' => 'category-cat2', 'count' => 5 }
          ],
          providers: [
            { 'name' => 'Provider A', 'eid' => 'provider-a', 'count' => 3 }
          ]
        }
      }
    }

    response_b = {
      source: 'node_b',
      url: 'http://example.com/b',
      status: 200,
      success: true,
      data: { 'results' => [],
              facets: {
                categories: [
                  { name: 'Category 1', eid: 'category-cat1', count: 4 },
                  { name: 'Category 3', eid: 'category-cat3', count: 1 }
                ],
                providers: [
                  { name: 'Provider A', eid: 'provider-a', count: 2 },
                  { name: 'Provider B', eid: 'provider-b', count: 7 }
                ]
              },
      }
    }

    merged = merger.merge_api_responses(response_a, response_b)

    facets = merged['facets']
    assert facets.is_a?(Hash), 'facets should be a Hash'

    # Categories
    categories = facets['categories']
    eids = categories.map { |i| i['eid'] }
    assert_includes eids, 'category-cat3', 'should include category-cat3 from second response'
    assert_equal 3, categories.size, 'should have 3 unique categories by eid'

    cat1 = categories.find { |i| i['eid'] == 'category-cat1' }
    assert_equal 6, cat1['count'], 'counts for category-cat1 should be summed (2 + 4)'

    cat2 = categories.find { |i| i['eid'] == 'category-cat2' }
    assert_equal 5, cat2['count']

    cat3 = categories.find { |i| i['eid'] == 'category-cat3' }
    assert_equal 1, cat3['count']

    # Providers
    providers = facets['providers']
    assert_equal 2, providers.size, 'should have 2 unique providers by eid'

    prov_a = providers.find { |i| i['eid'] == 'provider-a' }
    assert_equal 5, prov_a['count'], 'counts for provider-a should be summed (3 + 2)'

    prov_b = providers.find { |i| i['eid'] == 'provider-b' }
    assert_equal 7, prov_b['count']
  end

  test 'merges facets from only-top-level parsed facets' do
    merger = DummyMerger.new
    response_b = {
      source: 'node_b',
      url: 'http://example.com/b',
      status: 200,
      success: true,
      data: { 'results' => [],
            facets: {
        categories: [
          { name: 'Category 1', eid: 'category-cat1', count: 4 },
          { name: 'Category 3', eid: 'category-cat3', count: 1 }
        ]
      }, }
    }

    merged = merger.merge_api_responses(response_b)
    categories = merged['facets']['categories']
    assert_equal ['category-cat1','category-cat3'].sort, categories.map{ |i| i['eid'] }.sort
  end

  test 'sorts facets within each group by count descending' do
    merger = DummyMerger.new

    response_a = {
      source: 'node_a', url: 'http://example.com/a', status: 200, success: true,
      data: { 'results' => [], facets: {
        categories: [
          { name: 'A', eid: 'a', count: 1 },
          { name: 'B', eid: 'b', count: 7 }
        ],
        providers: [
          { name: 'X', eid: 'x', count: 2 }
        ]
      } }
    }

    response_b = {
      source: 'node_b', url: 'http://example.com/b', status: 200, success: true,
      data: { 'results' => [], facets: {
        categories: [
          { name: 'C', eid: 'c', count: 5 }
        ],
        providers: [
          { name: 'Y', eid: 'y', count: 9 },
          { name: 'X', eid: 'x', count: 1 }
        ]
      } }
    }

    merged = merger.merge_api_responses(response_a, response_b)

    cats = merged['facets']['categories']
    assert_equal %w[b c a], cats.map { |i| i['eid'] }, 'categories should be sorted by count desc (7,5,1)'

    provs = merged['facets']['providers']
    # X count should sum to 3 making order y(9), x(3)
    assert_equal %w[y x], provs.map { |i| i['eid'] }, 'providers should be sorted by count desc after summing'
  end
end
