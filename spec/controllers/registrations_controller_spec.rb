# frozen_string_literal: true

require 'spec_helper'

describe RegistrationsController do
  include TermsHelper

  before do
    stub_feature_flags(invisible_captcha: false)
  end

  describe '#create' do
    let(:base_user_params) { { name: 'new_user', username: 'new_username', email: 'new@user.com', password: 'Any_password' } }
    let(:user_params) { { user: base_user_params } }

    context 'email confirmation' do
      around do |example|
        perform_enqueued_jobs do
          example.run
        end
      end

      context 'when send_user_confirmation_email is false' do
        it 'signs the user in' do
          stub_application_setting(send_user_confirmation_email: false)

          expect { post(:create, params: user_params) }.not_to change { ActionMailer::Base.deliveries.size }
          expect(subject.current_user).not_to be_nil
        end
      end

      context 'when send_user_confirmation_email is true' do
        it 'does not authenticate user and sends confirmation email' do
          stub_application_setting(send_user_confirmation_email: true)

          post(:create, params: user_params)

          expect(ActionMailer::Base.deliveries.last.to.first).to eq(user_params[:user][:email])
          expect(subject.current_user).to be_nil
        end
      end

      context 'when signup_enabled? is false' do
        it 'redirects to sign_in' do
          stub_application_setting(signup_enabled: false)

          expect { post(:create, params: user_params) }.not_to change(User, :count)
          expect(response).to redirect_to(new_user_session_path)
        end
      end
    end

    context 'when reCAPTCHA is enabled' do
      def fail_recaptcha
        # Without this, `verify_recaptcha` arbitrarily returns true in test env
        Recaptcha.configuration.skip_verify_env.delete('test')
      end

      before do
        stub_application_setting(recaptcha_enabled: true)
      end

      it 'displays an error when the reCAPTCHA is not solved' do
        fail_recaptcha

        post(:create, params: user_params)

        expect(response).to render_template(:new)
        expect(flash[:alert]).to include 'There was an error with the reCAPTCHA. Please solve the reCAPTCHA again.'
      end

      it 'redirects to the dashboard when the recaptcha is solved' do
        # Avoid test ordering issue and ensure `verify_recaptcha` returns true
        unless Recaptcha.configuration.skip_verify_env.include?('test')
          Recaptcha.configuration.skip_verify_env << 'test'
        end

        post(:create, params: user_params)

        expect(flash[:notice]).to include 'Welcome! You have signed up successfully.'
      end

      it 'does not require reCAPTCHA if disabled by feature flag' do
        stub_feature_flags(registrations_recaptcha: false)
        fail_recaptcha

        post(:create, params: user_params)

        expect(controller).not_to receive(:verify_recaptcha)
        expect(flash[:alert]).to be_nil
        expect(flash[:notice]).to include 'Welcome! You have signed up successfully.'
      end
    end

    context 'when invisible captcha is enabled' do
      before do
        stub_feature_flags(invisible_captcha: true)
        InvisibleCaptcha.timestamp_threshold = treshold
      end

      let(:treshold) { 4 }
      let(:session_params) { { invisible_captcha_timestamp: form_rendered_time.iso8601 } }
      let(:form_rendered_time) { Time.current }
      let(:submit_time) { form_rendered_time + treshold }
      let(:auth_log_attributes) do
        {
          message: auth_log_message,
          env: :invisible_captcha_signup_bot_detected,
          ip: '0.0.0.0',
          request_method: 'POST',
          fullpath: '/users'
        }
      end

      describe 'the honeypot has not been filled and the signup form has not been submitted too quickly' do
        it 'creates an account' do
          travel_to(submit_time) do
            expect { post(:create, params: user_params, session: session_params) }.to change(User, :count).by(1)
          end
        end
      end

      describe 'honeypot spam detection' do
        let(:user_params) { super().merge(firstname: 'Roy', lastname: 'Batty') }
        let(:auth_log_message) { 'Invisible_Captcha_Honeypot_Request' }

        it 'logs the request, refuses to create an account and renders an empty body' do
          travel_to(submit_time) do
            expect(Gitlab::Metrics).to receive(:counter)
              .with(:bot_blocked_by_invisible_captcha_honeypot, 'Counter of blocked sign up attempts with filled honeypot')
              .and_call_original
            expect(Gitlab::AuthLogger).to receive(:error).with(auth_log_attributes).once
            expect { post(:create, params: user_params, session: session_params) }.not_to change(User, :count)
            expect(response).to have_gitlab_http_status(200)
            expect(response.body).to be_empty
          end
        end
      end

      describe 'timestamp spam detection' do
        let(:auth_log_message) { 'Invisible_Captcha_Timestamp_Request' }

        context 'the sign up form has been submitted without the invisible_captcha_timestamp parameter' do
          let(:session_params) { nil }

          it 'logs the request, refuses to create an account and displays a flash alert' do
            travel_to(submit_time) do
              expect(Gitlab::Metrics).to receive(:counter)
                .with(:bot_blocked_by_invisible_captcha_timestamp, 'Counter of blocked sign up attempts with invalid timestamp')
                .and_call_original
              expect(Gitlab::AuthLogger).to receive(:error).with(auth_log_attributes).once
              expect { post(:create, params: user_params, session: session_params) }.not_to change(User, :count)
              expect(response).to redirect_to(new_user_session_path)
              expect(flash[:alert]).to include 'That was a bit too quick! Please resubmit.'
            end
          end
        end

        context 'the sign up form has been submitted too quickly' do
          let(:submit_time) { form_rendered_time }

          it 'logs the request, refuses to create an account and displays a flash alert' do
            travel_to(submit_time) do
              expect(Gitlab::Metrics).to receive(:counter)
                .with(:bot_blocked_by_invisible_captcha_timestamp, 'Counter of blocked sign up attempts with invalid timestamp')
                .and_call_original
              expect(Gitlab::AuthLogger).to receive(:error).with(auth_log_attributes).once
              expect { post(:create, params: user_params, session: session_params) }.not_to change(User, :count)
              expect(response).to redirect_to(new_user_session_path)
              expect(flash[:alert]).to include 'That was a bit too quick! Please resubmit.'
            end
          end
        end
      end
    end

    context 'when terms are enforced' do
      before do
        enforce_terms
      end

      it 'redirects back with a notice when the checkbox was not checked' do
        post :create, params: user_params

        expect(flash[:alert]).to match /you must accept our terms/i
      end

      it 'creates the user with agreement when terms are accepted' do
        post :create, params: user_params.merge(terms_opt_in: '1')

        expect(subject.current_user).to be_present
        expect(subject.current_user.terms_accepted?).to be(true)
      end
    end

    it "logs a 'User Created' message" do
      stub_feature_flags(registrations_recaptcha: false)

      expect(Gitlab::AppLogger).to receive(:info).with(/\AUser Created: username=new_username email=new@user.com.+\z/).and_call_original

      post(:create, params: user_params)
    end

    it 'handles when params are new_user' do
      post(:create, params: { new_user: base_user_params })

      expect(subject.current_user).not_to be_nil
    end
  end

  describe '#destroy' do
    let(:user) { create(:user) }

    before do
      sign_in(user)
    end

    def expect_failure(message)
      expect(flash[:alert]).to eq(message)
      expect(response.status).to eq(303)
      expect(response).to redirect_to profile_account_path
    end

    def expect_password_failure
      expect_failure('Invalid password')
    end

    def expect_username_failure
      expect_failure('Invalid username')
    end

    def expect_success
      expect(flash[:notice]).to eq 'Account scheduled for removal.'
      expect(response.status).to eq(303)
      expect(response).to redirect_to new_user_session_path
    end

    context 'user requires password confirmation' do
      it 'fails if password confirmation is not provided' do
        post :destroy

        expect_password_failure
      end

      it 'fails if password confirmation is wrong' do
        post :destroy, params: { password: 'wrong password' }

        expect_password_failure
      end

      it 'succeeds if password is confirmed' do
        post :destroy, params: { password: '12345678' }

        expect_success
      end
    end

    context 'user does not require password confirmation' do
      before do
        stub_application_setting(password_authentication_enabled_for_web: false)
        stub_application_setting(password_authentication_enabled_for_git: false)
      end

      it 'fails if username confirmation is not provided' do
        post :destroy

        expect_username_failure
      end

      it 'fails if username confirmation is wrong' do
        post :destroy, params: { username: 'wrong username' }

        expect_username_failure
      end

      it 'succeeds if username is confirmed' do
        post :destroy, params: { username: user.username }

        expect_success
      end
    end
  end
end
