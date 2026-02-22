module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_token, only: :create

      rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
        render json: { error: "Too many requests" }, status: :too_many_requests
      }

      def create
        if user = User.active.authenticate_by(email_address: params[:email_address], password: params[:password])
          session = user.sessions.start!(user_agent: request.user_agent, ip_address: request.remote_ip)

          render json: {
            token: session.token,
            user: user_json(user)
          }, status: :created
        else
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end

      def destroy
        Current.session.destroy!
        head :no_content
      end

      private
        def user_json(user)
          {
            id: user.id,
            name: user.name,
            email_address: user.email_address,
            bio: user.bio,
            role: user.role,
            avatar_url: user.avatar.attached? ? polymorphic_url(user.avatar) : nil
          }
        end
    end
  end
end
