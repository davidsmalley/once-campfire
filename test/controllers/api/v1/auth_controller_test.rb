require "test_helper"

class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  test "sign in with valid credentials returns token" do
    assert_difference -> { Session.count }, +1 do
      post api_v1_auth_sign_in_url, params: { email_address: "david@37signals.com", password: "secret123456" }, as: :json
    end

    assert_response :created

    json = response.parsed_body
    assert json["token"].present?
    assert_equal "David", json["user"]["name"]
    assert_equal "david@37signals.com", json["user"]["email_address"]
  end

  test "sign in with invalid credentials returns unauthorized" do
    post api_v1_auth_sign_in_url, params: { email_address: "david@37signals.com", password: "wrong" }, as: :json

    assert_response :unauthorized
    assert_equal "Invalid email or password", response.parsed_body["error"]
  end

  test "sign out destroys session" do
    session = sessions(:david_safari)

    assert_difference -> { Session.count }, -1 do
      delete api_v1_auth_sign_out_url, headers: { "Authorization" => "Bearer #{session.token}" }
    end

    assert_response :no_content
  end

  test "sign out without token returns unauthorized" do
    delete api_v1_auth_sign_out_url

    assert_response :unauthorized
  end
end
