module Api
  module V1
    class RoomsController < BaseController
      before_action :set_room, only: %i[show]

      def index
        rooms = Current.user.rooms.ordered

        render json: rooms.map { |room| room_json(room) }
      end

      def show
        render json: room_json(@room, include_members: true)
      end

      private
        def set_room
          @room = Current.user.rooms.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found
        end

        def room_json(room, include_members: false)
          membership = room.memberships.find_by(user: Current.user)

          json = {
            id: room.id,
            name: room.name,
            type: room.type.demodulize.downcase,
            created_at: room.created_at,
            updated_at: room.updated_at,
            unread: membership&.unread_at.present?,
            involvement: membership&.involvement
          }

          if include_members
            json[:members] = room.users.active.ordered.map do |user|
              { id: user.id, name: user.name }
            end
          end

          json
        end
    end
  end
end
