require "test_helper"

class Api::V1::BoostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}" }
    @message = messages(:first)
  end

  test "create adds a boost to a message" do
    assert_difference -> { @message.boosts.count }, +1 do
      post api_v1_message_boosts_url(@message),
        params: { boost: { content: "🎉" } },
        headers: @headers,
        as: :json
    end

    assert_response :created

    json = response.parsed_body
    assert_equal "🎉", json["content"]
    assert_equal users(:david).id, json["booster"]["id"]
    assert_equal @message.id, json["message_id"]
  end

  test "create without auth returns unauthorized" do
    post api_v1_message_boosts_url(@message),
      params: { boost: { content: "👍" } },
      as: :json

    assert_response :unauthorized
  end

  test "destroy removes own boost" do
    boost = @message.boosts.create!(content: "🔥", booster: users(:david))

    assert_difference -> { Boost.count }, -1 do
      delete api_v1_message_boost_url(@message, boost), headers: @headers
    end

    assert_response :no_content
  end

  test "destroy cannot remove another user's boost" do
    boost = boosts(:first)  # david's boost
    jason_session = Session.create!(user: users(:jason), user_agent: "test", ip_address: "127.0.0.1")

    assert_raises ActiveRecord::RecordNotFound do
      delete api_v1_message_boost_url(@message, boost),
        headers: { "Authorization" => "Bearer #{jason_session.token}" }
    end
  end

  test "create for unreachable message returns not found" do
    # Create a message in a room david doesn't have access to
    # Use a non-existent message ID instead
    post api_v1_message_boosts_url(999999),
      params: { boost: { content: "👍" } },
      headers: @headers,
      as: :json

    assert_response :not_found
  end
end
