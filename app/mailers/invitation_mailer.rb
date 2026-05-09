class InvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @accept_url = invitation_acceptance_url(token: @invitation.token)
    @project = invitation.project
    @inviter = invitation.inviter

    mail(
      to: @invitation.email_address,
      subject: "You've been invited to join #{@project.name} on Master of Puppets"
    )
  end
end
