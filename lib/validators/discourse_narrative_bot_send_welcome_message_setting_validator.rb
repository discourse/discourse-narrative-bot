class DiscourseNarrativeBotSendWelcomeMessageSettingValidator
  def initialize(opts={})
    @opts = opts
  end

  def valid_value?(val)
    return true if val == 'f'
    return false if 
    true
  end

  def error_message
    if SiteSetting.slack_outbound_webhook_url.blank? && SiteSetting.slack_access_token.blank?
      I18n.t('site_settings.errors.slack_api_configs_are_empty')
    elsif !valid_webhook_url?
      I18n.t('site_settings.errors.invalid_webhook_url')
    elsif SiteSetting.slack_discourse_username.blank?
      I18n.t('site_settings.errors.slack_discourse_username_is_empty')
    elsif !valid_slack_username?
      I18n.t('site_settings.errors.invalid_username')
    end
  end
end
