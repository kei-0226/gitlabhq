# frozen_string_literal: true

module InvisibleCaptcha
  extend ActiveSupport::Concern

  included do
    invisible_captcha only: :create, on_spam: :on_honeypot_spam_callback, on_timestamp_spam: :on_timestamp_spam_callback
  end

  def on_honeypot_spam_callback
    return unless Feature.enabled?(:invisible_captcha)

    invisible_captcha_honeypot_counter.increment
    log_request('Invisible_Captcha_Honeypot_Request')

    head(200)
  end

  def on_timestamp_spam_callback
    return unless Feature.enabled?(:invisible_captcha)

    invisible_captcha_timestamp_counter.increment
    log_request('Invisible_Captcha_Timestamp_Request')

    redirect_to new_user_session_path, alert: InvisibleCaptcha.timestamp_error_message
  end

  def invisible_captcha_honeypot_counter
    @invisible_captcha_honeypot_counter ||=
      Gitlab::Metrics.counter(:bot_blocked_by_invisible_captcha_honeypot,
                              'Counter of blocked sign up attempts with filled honeypot')
  end

  def invisible_captcha_timestamp_counter
    @invisible_captcha_timestamp_counter ||=
      Gitlab::Metrics.counter(:bot_blocked_by_invisible_captcha_timestamp,
                              'Counter of blocked sign up attempts with invalid timestamp')
  end

  def log_request(message)
    request_information = {
      message: message,
      env: :invisible_captcha_signup_bot_detected,
      ip: request.ip,
      request_method: request.request_method,
      fullpath: request.fullpath
    }

    Gitlab::AuthLogger.error(request_information)
  end
end
