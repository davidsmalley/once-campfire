module Api
  module V1
    class BoostsController < BaseController
      before_action :set_message

      def create
        @boost = @message.boosts.create!(boost_params)

        render json: boost_json(@boost), status: :created
      end

      def destroy
        @boost = Current.user.boosts.find(params[:id])
        @boost.destroy!

        head :no_content
      end

      private
        def set_message
          @message = Current.user.reachable_messages.find(params[:message_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found
        end

        def boost_params
          params.require(:boost).permit(:content)
        end

        def boost_json(boost)
          {
            id: boost.id,
            content: boost.content,
            created_at: boost.created_at,
            booster: {
              id: boost.booster_id,
              name: boost.booster.name
            },
            message_id: boost.message_id
          }
        end
    end
  end
end
