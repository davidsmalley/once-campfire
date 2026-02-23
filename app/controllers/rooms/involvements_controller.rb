class Rooms::InvolvementsController < ApplicationController
  include RoomScoped

  def show
    @involvement = @membership.involvement
  end

  def update
    involvement = params[:involvement].to_s

    unless involvement.in?(Membership.involvements.keys)
      return redirect_to room_involvement_url(@room), alert: "Invalid involvement setting"
    end

    @membership.update! involvement: involvement

    broadcast_visibility_changes
    redirect_to room_involvement_url(@room)
  end

  private
    def broadcast_visibility_changes
      case
      when @room.direct?
        # Do nothing
      when @membership.involved_in_invisible?
        broadcast_remove_to @membership.user, :rooms, target: [ @room, :list ]
      when @membership.involvement_previously_was.inquiry.invisible?
        broadcast_prepend_to @membership.user, :rooms, target: :shared_rooms, partial: "users/sidebars/rooms/shared", locals: { room: @room }
      end
    end
end
