require "test_helper"

class Api::V1::KeyBundlesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session = sessions(:david_safari)
    @headers = { "Authorization" => "Bearer #{@session.token}", "Content-Type" => "application/json" }
  end

  test "upload key bundle" do
    post api_v1_users_me_keys_url, params: {
      identity_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
      signed_pre_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
      signed_pre_key_signature: Base64.strict_encode64(SecureRandom.random_bytes(64)),
      signed_pre_key_id: 1,
      pre_keys: [
        { key_id: 1, public_key: Base64.strict_encode64(SecureRandom.random_bytes(32)) },
        { key_id: 2, public_key: Base64.strict_encode64(SecureRandom.random_bytes(32)) }
      ]
    }.to_json, headers: @headers

    assert_response :created
    assert_not_nil users(:david).reload.key_bundle
    assert_equal 2, users(:david).pre_keys.count
  end

  test "upload key bundle replaces existing bundle" do
    upload_keys_for(users(:david))

    post api_v1_users_me_keys_url, params: {
      identity_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
      signed_pre_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
      signed_pre_key_signature: Base64.strict_encode64(SecureRandom.random_bytes(64)),
      signed_pre_key_id: 2,
      pre_keys: []
    }.to_json, headers: @headers

    assert_response :created
    assert_equal 2, users(:david).reload.key_bundle.signed_pre_key_id
  end

  test "fetch key bundle consumes one pre-key" do
    upload_keys_for(users(:david))
    initial_count = users(:david).pre_keys.count

    get api_v1_users_keys_url(users(:david).id), headers: @headers

    assert_response :success
    body = response.parsed_body
    assert body["identity_key"].present?
    assert body["signed_pre_key"].present?
    assert body["pre_key"].present?
    assert_equal initial_count - 1, users(:david).pre_keys.count
  end

  test "fetch key bundle returns null pre_key when all consumed" do
    user = users(:david)
    user.create_key_bundle!(
      identity_key: SecureRandom.random_bytes(32),
      signed_pre_key: SecureRandom.random_bytes(32),
      signed_pre_key_signature: SecureRandom.random_bytes(64),
      signed_pre_key_id: 1
    )

    get api_v1_users_keys_url(user.id), headers: @headers

    assert_response :success
    body = response.parsed_body
    assert body["identity_key"].present?
    assert_nil body["pre_key"]
  end

  test "fetch key bundle returns 404 if no keys uploaded" do
    get api_v1_users_keys_url(users(:jason).id), headers: @headers
    assert_response :not_found
  end

  test "delete keys" do
    upload_keys_for(users(:david))

    delete api_v1_users_me_keys_url, headers: @headers
    assert_response :no_content
    assert_nil users(:david).reload.key_bundle
    assert_equal 0, users(:david).pre_keys.count
  end

  test "delete keys when none exist" do
    delete api_v1_users_me_keys_url, headers: @headers
    assert_response :no_content
  end

  test "upload without auth returns unauthorized" do
    post api_v1_users_me_keys_url, params: {
      identity_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
      signed_pre_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
      signed_pre_key_signature: Base64.strict_encode64(SecureRandom.random_bytes(64)),
      signed_pre_key_id: 1
    }.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  private
    def upload_keys_for(user)
      user.create_key_bundle!(
        identity_key: SecureRandom.random_bytes(32),
        signed_pre_key: SecureRandom.random_bytes(32),
        signed_pre_key_signature: SecureRandom.random_bytes(64),
        signed_pre_key_id: 1
      )
      3.times do |i|
        user.pre_keys.create!(key_id: i + 1, public_key: SecureRandom.random_bytes(32))
      end
    end
end
