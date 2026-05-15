class ChatSessions::MessagesController < ApplicationController
  include ChatSessionScoped

  def create
    @user_message      = @chat_session.messages.create!(
      role:           :user,
      content_blocks: [ { type: "text", text: params.require(:content) } ],
      status:         :completed,
      model:          @chat_session.model,
      provider:       @chat_session.provider
    )
    @assistant_message = @chat_session.messages.create!(
      role:           :assistant,
      content_blocks: [],
      status:         :pending,
      model:          @chat_session.model,
      provider:       @chat_session.provider
    )
    @assistant_message.advance_later

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat_session }
    end
  end
end
