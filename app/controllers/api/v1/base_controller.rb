module Api
  module V1
    class BaseController < ActionController::API
      include BlockBannedRequests

      rescue_from ActiveRecord::RecordNotFound do
        render_not_found
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      rescue_from ArgumentError do |e|
        render json: { error: e.message }, status: :unprocessable_entity
      end

      before_action :authenticate_token

      private
        def authenticate_token
          if token = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
            if session = Session.find_by(token: token)
              session.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
              Current.session = session
              Current.user = session.user
            else
              render_unauthorized
            end
          else
            render_unauthorized
          end
        end

        def render_unauthorized
          render json: { error: "Unauthorized" }, status: :unauthorized
        end

        def render_forbidden
          render json: { error: "Forbidden" }, status: :forbidden
        end

        def render_not_found
          render json: { error: "Not found" }, status: :not_found
        end
    end
  end
end
