require "test_helper"

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}" }
  end

  test "me returns current user profile" do
    get api_v1_users_me_url, headers: @headers

    assert_response :success

    json = response.parsed_body
    assert_equal users(:david).id, json["id"]
    assert_equal "David", json["name"]
    assert_equal "david@37signals.com", json["email_address"]
    assert_equal "administrator", json["role"]
  end

  test "me without auth returns unauthorized" do
    get api_v1_users_me_url

    assert_response :unauthorized
  end

  test "update_me updates current user" do
    put api_v1_users_me_url,
      params: { user: { bio: "New bio" } },
      headers: @headers,
      as: :json

    assert_response :success

    json = response.parsed_body
    assert_equal "New bio", json["bio"]
    assert_equal users(:david).reload.bio, "New bio"
  end

  test "update_me updates name" do
    put api_v1_users_me_url,
      params: { user: { name: "David H" } },
      headers: @headers,
      as: :json

    assert_response :success
    assert_equal "David H", response.parsed_body["name"]
  end

  test "show returns another user" do
    get api_v1_user_url(users(:jason)), headers: @headers

    assert_response :success

    json = response.parsed_body
    assert_equal users(:jason).id, json["id"]
    assert_equal "Jason", json["name"]
    # Should not include email for other users
    assert_nil json["email_address"]
  end

  test "show for non-existent user returns not found" do
    get api_v1_user_url(999999), headers: @headers

    assert_response :not_found
  end
end
