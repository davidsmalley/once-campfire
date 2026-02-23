module Api
  module V1
    class PushSubscriptionsController < BaseController
      def create
        if existing = Current.user.push_subscriptions.ios.find_by(device_token: push_params[:device_token])
          existing.touch
          render json: subscription_json(existing)
        else
          subscription = Current.user.push_subscriptions.create!(
            platform: "ios",
            device_token: push_params[:device_token],
            user_agent: request.user_agent
          )
          render json: subscription_json(subscription), status: :created
        end
      end

      def destroy
        subscription = Current.user.push_subscriptions.ios.find(params[:id])
        subscription.destroy!
        head :no_content
      end

      def destroy_by_token
        subscription = Current.user.push_subscriptions.ios.find_by!(device_token: params[:device_token])
        subscription.destroy!
        head :no_content
      end

      private
        def push_params
          params.require(:push_subscription).permit(:device_token)
        end

        def subscription_json(subscription)
          {
            id: subscription.id,
            platform: subscription.platform,
            device_token: subscription.device_token,
            created_at: subscription.created_at
          }
        end
    end
  end
end
