module Api
  module V1
    class InvolvementsController < BaseController
      before_action :set_room_and_membership

      def show
        render json: involvement_json
      end

      def update
        involvement = params[:involvement].to_s

        unless involvement.in?(Membership.involvements.keys)
          return render json: { error: "Invalid involvement. Must be one of: #{Membership.involvements.keys.join(', ')}" }, status: :unprocessable_entity
        end

        @membership.update!(involvement: involvement)
        render json: involvement_json
      end

      private
        def set_room_and_membership
          @room = Current.user.rooms.find(params[:room_id])
          @membership = @room.memberships.find_by!(user: Current.user)
        rescue ActiveRecord::RecordNotFound
          render_not_found
        end

        def involvement_json
          {
            room_id: @room.id,
            involvement: @membership.involvement
          }
        end
    end
  end
end
