module Jobs
  class SendDefaultWelcomeMessage < Jobs::Base
    def execute(args)
      if user = User.find_by(id: args[:user_id])
        type = user.invited_by ? 'welcome_invite' : 'welcome_user'
        params = SystemMessage.new(user).defaults

        title = I18n.t("system_messages.#{type}.subject_template", params)
        raw = I18n.t("system_messages.#{type}.text_body_template", params)

        PostCreator.create!(
          User.find(-2),
          title: title,
          raw: raw,
          archetype: Archetype.private_message,
          target_usernames: user.username,
          skip_validations: true
        )
      end
    end
  end
end
