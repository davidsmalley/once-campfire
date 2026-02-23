require "test_helper"

class Api::V1::SearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}" }
  end

  test "create searches messages and returns results" do
    post api_v1_searches_url,
      params: { q: "hello" },
      headers: @headers,
      as: :json

    assert_response :success

    json = response.parsed_body
    assert_equal "hello", json["query"]
    assert json["messages"].is_a?(Array)
  end

  test "create records the search" do
    assert_difference -> { users(:david).searches.count }, +1 do
      post api_v1_searches_url,
        params: { q: "test search" },
        headers: @headers,
        as: :json
    end
  end

  test "create without query returns unprocessable" do
    post api_v1_searches_url,
      params: { q: "" },
      headers: @headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "create without auth returns unauthorized" do
    post api_v1_searches_url,
      params: { q: "hello" },
      as: :json

    assert_response :unauthorized
  end
end
