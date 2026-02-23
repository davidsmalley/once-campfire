module Api
  module V1
    class SearchesController < BaseController
      def create
        if query.blank?
          return render json: { error: "Query is required" }, status: :unprocessable_entity
        end

        Current.user.searches.record(query)
        messages = Current.user.reachable_messages.search(query).last(100)

        render json: {
          query: query,
          messages: messages.map { |msg| message_json(msg) }
        }
      end

      private
        def query
          params[:q]&.gsub(/[^[:word:]]/, " ")
        end

        def message_json(message)
          {
            id: message.id,
            body: message.plain_text_body,
            created_at: message.created_at,
            room: {
              id: message.room_id,
              name: message.room.name
            },
            creator: {
              id: message.creator_id,
              name: message.creator.name
            }
          }
        end
    end
  end
end
