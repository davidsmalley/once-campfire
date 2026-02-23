module Api
  module V1
    class UsersController < BaseController
      rate_limit to: 10, within: 1.minute, only: :update_me, with: -> {
        render json: { error: "Too many requests" }, status: :too_many_requests
      }

      before_action :set_user, only: :show

      def me
        render json: user_json(Current.user, full: true)
      end

      def update_me
        if changing_sensitive_fields? && !current_password_valid?
          return render json: { error: "Current password is required to change email or password" }, status: :unprocessable_entity
        end

        Current.user.update!(user_params)
        render json: user_json(Current.user, full: true)
      end

      def show
        render json: user_json(@user)
      end

      private
        def set_user
          @user = User.active.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found
        end

        def user_params
          params.require(:user).permit(:name, :bio, :email_address, :password, :avatar)
        end

        def changing_sensitive_fields?
          user_params.key?(:password) || user_params.key?(:email_address)
        end

        def current_password_valid?
          params.dig(:user, :current_password).present? &&
            Current.user.authenticate(params.dig(:user, :current_password))
        end

        def user_json(user, full: false)
          json = {
            id: user.id,
            name: user.name,
            bio: user.bio,
            avatar_url: user.avatar.attached? ? polymorphic_url(user.avatar) : nil
          }

          if full
            json.merge!(
              email_address: user.email_address,
              role: user.role
            )
          end

          json
        end
    end
  end
end
