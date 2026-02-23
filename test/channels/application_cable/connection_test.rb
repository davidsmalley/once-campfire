require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  # Cookie-based auth (web clients)

  test "connects with valid session cookie" do
    cookies.signed[:session_token] = sessions(:david_safari).token

    connect

    assert_equal users(:david), connection.current_user
  end

  test "rejects connection with missing session cookie" do
    assert_reject_connection { connect }
  end

  test "rejects connection with invalid session cookie" do
    cookies.signed[:session_token] = -1

    assert_reject_connection { connect }
  end

  # Token-based auth (native/iOS clients)

  test "connects with valid bearer token in params" do
    connect params: { token: sessions(:david_safari).token }

    assert_equal users(:david), connection.current_user
  end

  test "rejects connection with invalid token in params" do
    assert_reject_connection { connect params: { token: "invalid_token" } }
  end

  test "rejects connection with blank token in params" do
    assert_reject_connection { connect params: { token: "" } }
  end

  test "cookie auth takes precedence when both provided" do
    cookies.signed[:session_token] = sessions(:david_safari).token

    connect params: { token: "some_other_token" }

    assert_equal users(:david), connection.current_user
  end
end
