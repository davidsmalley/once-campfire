module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include Authentication::SessionLookup

    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private
      def find_verified_user
        if verified_session = find_session_by_cookie || find_session_by_token
          verified_session.user
        else
          reject_unauthorized_connection
        end
      end

      # Token-based auth for native clients (iOS).
      # The client passes { token: "..." } in the ActionCable connection params.
      def find_session_by_token
        if token = request.params[:token].presence
          Session.find_by(token: token)
        end
      end
  end
end
