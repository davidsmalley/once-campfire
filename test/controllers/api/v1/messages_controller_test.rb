require "test_helper"

class Api::V1::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}" }
    @room = rooms(:designers)
  end

  test "index returns messages for a room" do
    get api_v1_room_messages_url(@room), headers: @headers

    assert_response :success

    messages = response.parsed_body
    assert messages.is_a?(Array)
  end

  test "create sends a message" do
    assert_difference -> { @room.messages.count }, +1 do
      post api_v1_room_messages_url(@room),
        params: { message: { body: "Hello from the API!" } },
        headers: @headers,
        as: :json
    end

    assert_response :created

    json = response.parsed_body
    assert_equal "Hello from the API!", json["body"]
    assert_equal users(:david).id, json["creator"]["id"]
  end

  test "create without auth returns unauthorized" do
    post api_v1_room_messages_url(@room),
      params: { message: { body: "Should fail" } },
      as: :json

    assert_response :unauthorized
  end
end
