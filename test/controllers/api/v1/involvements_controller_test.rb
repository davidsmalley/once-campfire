require "test_helper"

class Api::V1::InvolvementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}" }
    @room = rooms(:pets)
  end

  test "show returns involvement for room" do
    get api_v1_room_involvement_url(@room), headers: @headers

    assert_response :success

    json = response.parsed_body
    assert_equal @room.id, json["room_id"]
    assert_includes Membership.involvements.keys, json["involvement"]
  end

  test "show without auth returns unauthorized" do
    get api_v1_room_involvement_url(@room)

    assert_response :unauthorized
  end

  test "update changes involvement level" do
    put api_v1_room_involvement_url(@room),
      params: { involvement: "nothing" },
      headers: @headers,
      as: :json

    assert_response :success

    json = response.parsed_body
    assert_equal "nothing", json["involvement"]

    membership = @room.memberships.find_by(user: users(:david))
    assert_equal "nothing", membership.involvement
  end

  test "show for inaccessible room returns not found" do
    get api_v1_room_involvement_url(999999), headers: @headers

    assert_response :not_found
  end
end
