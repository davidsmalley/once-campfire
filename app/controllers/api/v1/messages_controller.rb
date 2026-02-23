module Api
  module V1
    class MessagesController < BaseController
      include ActiveStorage::SetCurrent

      before_action :set_room
      before_action :set_message, only: %i[show update destroy]
      before_action :ensure_can_administer, only: %i[update destroy]

      def index
        messages = find_paged_messages
        render json: messages.map { |msg| message_json(msg) }
      end

      def show
        render json: message_json(@message)
      end

      def create
        @message = @room.messages.create_with_attachment!(message_params)
        @message.broadcast_create

        render json: message_json(@message), status: :created
      end

      def update
        @message.update!(message_params)
        @message.broadcast_replace_to @room, :messages,
          target: [ @message, :presentation ],
          partial: "messages/presentation",
          attributes: { maintain_scroll: true }

        render json: message_json(@message)
      end

      def destroy
        @message.destroy
        @message.broadcast_remove
        head :no_content
      end

      private
        def set_room
          @room = Current.user.rooms.find(params[:room_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found
        end

        def set_message
          @message = @room.messages.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found
        end

        def ensure_can_administer
          render_forbidden unless Current.user.can_administer?(@message)
        end

        def find_paged_messages
          scope = @room.messages.with_creator.ordered

          if params[:before].present?
            scope.page_before(@room.messages.find(params[:before]))
          elsif params[:after].present?
            scope.page_after(@room.messages.find(params[:after]))
          else
            scope.last_page
          end
        end

        def message_params
          params.require(:message).permit(:body, :attachment, :client_message_id)
        end

        def message_json(message)
          {
            id: message.id,
            client_message_id: message.client_message_id,
            body: message.plain_text_body,
            body_html: message.body.to_s,
            content_type: message.content_type.to_s,
            created_at: message.created_at,
            updated_at: message.updated_at,
            creator: {
              id: message.creator_id,
              name: message.creator.name
            },
            boosts: message.boosts.map { |b| { id: b.id, content: b.content, booster_id: b.booster_id } }
          }
        end
    end
  end
end
