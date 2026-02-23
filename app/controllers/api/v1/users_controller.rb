module Api
  module V1
    class UsersController < BaseController
      before_action :set_user, only: :show

      def me
        render json: user_json(Current.user, full: true)
      end

      def update_me
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
