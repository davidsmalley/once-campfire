module Api
  module V1
    class KeyBundlesController < BaseController
      # POST /api/v1/users/me/keys
      def create
        ActiveRecord::Base.transaction do
          bundle = Current.user.key_bundle || Current.user.build_key_bundle
          bundle.update!(
            identity_key: decode_key(params[:identity_key]),
            signed_pre_key: decode_key(params[:signed_pre_key]),
            signed_pre_key_signature: decode_key(params[:signed_pre_key_signature]),
            signed_pre_key_id: params[:signed_pre_key_id]
          )

          if params[:pre_keys].present?
            params[:pre_keys].each do |pk|
              Current.user.pre_keys.find_or_create_by!(key_id: pk[:key_id]) do |pre_key|
                pre_key.public_key = decode_key(pk[:public_key])
              end
            end
          end
        end

        head :created
      end

      # GET /api/v1/users/:id/keys
      def show
        user = User.active.find(params[:id])
        bundle = user.key_bundle

        if bundle.nil?
          return render json: { error: "User has not uploaded encryption keys" }, status: :not_found
        end

        pre_key = user.pre_keys.order(:id).first

        response = {
          user_id: user.id,
          identity_key: encode_key(bundle.identity_key),
          signed_pre_key: {
            id: bundle.signed_pre_key_id,
            key: encode_key(bundle.signed_pre_key),
            signature: encode_key(bundle.signed_pre_key_signature)
          },
          pre_key: pre_key ? { id: pre_key.key_id, key: encode_key(pre_key.public_key) } : nil
        }

        pre_key&.destroy!

        render json: response
      end

      # DELETE /api/v1/users/me/keys
      def destroy
        Current.user.key_bundle&.destroy!
        Current.user.pre_keys.delete_all
        head :no_content
      end

      private
        def decode_key(base64_string)
          Base64.strict_decode64(base64_string)
        end

        def encode_key(binary)
          Base64.strict_encode64(binary)
        end
    end
  end
end
