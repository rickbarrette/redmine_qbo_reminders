#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Sending a reminder from an appointment, turning reminders on or off for a customer, and (administrators)
# sending a test email or running the reminders from the settings page
class AppointmentRemindersController < ApplicationController

  before_action :authorize_global, only: [:send_now, :opt_out, :opt_in]
  before_action :require_admin, only: [:test, :run]

  def send_now
    appointment = CustomerAppointment.find(params[:id])
    reminder = RedmineQboReminders::Sender.new.send_now(appointment, user: User.current)
    if reminder.nil?
      flash[:error] = l(:error_reminder_no_email)
    elsif reminder.sent?
      flash[:notice] = l(:notice_reminder_sent, email: reminder.email)
    else
      flash[:error] = l(:error_reminder_failed, error: reminder.error.to_s)
    end
    redirect_to customer_appointment_path(appointment)
  end

  def opt_out
    customer = Customer.find(params[:customer_id])
    ReminderOptOut.find_or_create_by!(customer_id: customer.id) { |o| o.user = User.current }
    flash[:notice] = l(:notice_reminders_off, customer: customer.name)
    redirect_back_or_default customer_path(customer)
  end

  def opt_in
    customer = Customer.find(params[:customer_id])
    ReminderOptOut.where(customer_id: customer.id).delete_all
    flash[:notice] = l(:notice_reminders_on, customer: customer.name)
    redirect_back_or_default customer_path(customer)
  end

  # A sample reminder to the address given (or the administrator's own), with the settings as they are on
  # the settings page, saved or not (its Send test email button submits the form here)
  def test
    settings = RedmineQboReminders::Settings.current
    if params[:settings].respond_to?(:to_unsafe_h)
      settings = RedmineQboReminders::Settings.new(Setting.plugin_redmine_qbo_reminders.to_h.merge(params[:settings].to_unsafe_h))
    end
    email = params[:email].to_s.strip.presence || User.current.mail
    starts_at = settings.zone.now.beginning_of_day + 1.day + 9.hours
    message = RedmineQboReminders::Message.new(
      settings: settings, starts_at: starts_at, uid: "test-#{Time.now.to_i}@#{settings.mail_domain}",
      values: { 'customer' => 'Jane Doe', 'first_name' => 'Jane', 'subject' => 'Sample appointment' }
                .merge(RedmineQboReminders::Message.plugin_values(nil))
                .merge(RedmineQboReminders::Message.when_values(starts_at))
    )
    AppointmentReminderMailer.reminder(message, email).deliver_now
    flash[:notice] = l(:notice_reminder_test_sent, email: email)
  rescue StandardError => e
    flash[:error] = l(:error_reminder_failed, error: "#{e.class}: #{e.message}")
  ensure
    redirect_to plugin_settings_path(:redmine_qbo_reminders)
  end

  def run
    if RedmineQboReminders::Settings.current.enabled?
      flash[:notice] = l(:notice_reminders_run, result: RedmineQboReminders::Sender.run.to_s)
    else
      flash[:error] = l(:error_reminders_disabled)
    end
    redirect_to plugin_settings_path(:redmine_qbo_reminders)
  end
end
