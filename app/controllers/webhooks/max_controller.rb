class Webhooks::MaxController < ActionController::API
  def process_payload
    Webhooks::MaxEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end
end

