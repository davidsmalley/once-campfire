require "test_helper"

class Api::V1::PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}" }
  end

  test "register new iOS device token" do
    assert_difference -> { Push::Subscription.ios.count }, +1 do
      post api_v1_push_subscriptions_url,
        params: { push_subscription: { device_token: "new_device_token_abc123" } },
        headers: @headers,
        as: :json
    end

    assert_response :created

    json = response.parsed_body
    assert_equal "ios", json["platform"]
    assert_equal "new_device_token_abc123", json["device_token"]
    assert json["id"].present?
  end

  test "re-registering existing device token touches record instead of creating" do
    existing = push_subscriptions(:david_iphone)

    assert_no_difference -> { Push::Subscription.count } do
      post api_v1_push_subscriptions_url,
        params: { push_subscription: { device_token: existing.device_token } },
        headers: @headers,
        as: :json
    end

    assert_response :ok
    assert_equal existing.id, response.parsed_body["id"]
  end

  test "unregister device by subscription ID" do
    subscription = push_subscriptions(:david_iphone)

    assert_difference -> { Push::Subscription.count }, -1 do
      delete api_v1_push_subscription_url(subscription),
        headers: @headers
    end

    assert_response :no_content
  end

  test "unregister device by token" do
    subscription = push_subscriptions(:david_iphone)

    assert_difference -> { Push::Subscription.count }, -1 do
      delete api_v1_push_subscription_by_token_url(device_token: subscription.device_token),
        headers: @headers
    end

    assert_response :no_content
  end

  test "cannot delete another user's subscription" do
    other_session = Session.create!(user: users(:jason), user_agent: "test", ip_address: "127.0.0.1")
    other_headers = { "Authorization" => "Bearer #{other_session.token}" }

    subscription = push_subscriptions(:david_iphone)

    assert_no_difference -> { Push::Subscription.count } do
      delete api_v1_push_subscription_url(subscription),
        headers: other_headers
    end

    assert_response :not_found
  end

  test "requires authentication" do
    post api_v1_push_subscriptions_url,
      params: { push_subscription: { device_token: "abc123" } },
      as: :json

    assert_response :unauthorized
  end

  test "register with missing device token returns error" do
    post api_v1_push_subscriptions_url,
      params: { push_subscription: { device_token: "" } },
      headers: @headers,
      as: :json

    assert_response :unprocessable_entity
  end
end
