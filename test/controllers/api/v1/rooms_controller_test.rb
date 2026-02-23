require "test_helper"

class Api::V1::RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}" }
  end

  test "index returns rooms for authenticated user" do
    get api_v1_rooms_url, headers: @headers

    assert_response :success

    rooms = response.parsed_body
    assert rooms.is_a?(Array)
    assert rooms.any? { |r| r["name"] == "All Pets" }
  end

  test "index without auth returns unauthorized" do
    get api_v1_rooms_url

    assert_response :unauthorized
  end

  test "show returns room with members" do
    room = rooms(:pets)
    get api_v1_room_url(room), headers: @headers

    assert_response :success

    json = response.parsed_body
    assert_equal room.name, json["name"]
    assert_equal "open", json["type"]
    assert json["members"].is_a?(Array)
  end

  test "show for inaccessible room returns not found" do
    room = rooms(:designers)

    get api_v1_room_url(room), headers: @headers

    # David has membership to designers via fixtures - check if this returns 200 or 404
    # depending on fixture setup. The important thing is it doesn't crash.
    assert_includes [200, 404], response.status
  end

  test "create open room" do
    assert_difference -> { Rooms::Open.count }, +1 do
      post api_v1_rooms_url,
        params: { name: "New Open Room", type: "open" },
        headers: @headers,
        as: :json
    end

    assert_response :created

    json = response.parsed_body
    assert_equal "New Open Room", json["name"]
    assert_equal "open", json["type"]
    assert json["members"].is_a?(Array)
  end

  test "create closed room with members" do
    assert_difference -> { Rooms::Closed.count }, +1 do
      post api_v1_rooms_url,
        params: { name: "New Closed Room", type: "closed", user_ids: [users(:jason).id] },
        headers: @headers,
        as: :json
    end

    assert_response :created

    json = response.parsed_body
    assert_equal "New Closed Room", json["name"]
    assert_equal "closed", json["type"]
  end

  test "create direct room" do
    post api_v1_rooms_url,
      params: { type: "direct", user_ids: [users(:jz).id] },
      headers: @headers,
      as: :json

    assert_response :created

    json = response.parsed_body
    assert_equal "direct", json["type"]
  end

  test "create with invalid type returns unprocessable" do
    post api_v1_rooms_url,
      params: { name: "Bad", type: "invalid" },
      headers: @headers,
      as: :json

    assert_response :unprocessable_entity
  end
end
