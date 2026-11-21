#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)
require File.expand_path('../../../redmine_qbo/test/qbo_fake_service', __dir__)

class AppointmentRemindersControllerTest < Redmine::IntegrationTest
  include QboRemindersTestHelper
  include QboFakeServiceHelper

  def setup
    travel_to Time.utc(2026, 11, 20, 12)
    @customer = create_customer
    @appointment = create_appointment
  end

  def login(*permissions)
    allow(*permissions)
    reset!
    log_user('jsmith', 'jsmith')
  end

  # ---- an appointment's reminder ----

  def test_send_now_needs_permission
    login(:view_customer_appointments)
    post "/customer_appointments/#{@appointment.id}/reminder"
    assert_response :forbidden
    assert_empty ActionMailer::Base.deliveries
  end

  def test_send_now
    login(:view_customer_appointments, :send_appointment_reminders)
    post "/customer_appointments/#{@appointment.id}/reminder"
    assert_redirected_to "/customer_appointments/#{@appointment.id}"
    assert_equal I18n.t(:notice_reminder_sent, email: 'jane@example.com'), flash[:notice]
    assert_equal ['jane@example.com'], ActionMailer::Base.deliveries.last.to
    assert_equal User.find(2), AppointmentReminder.last.sent_by
  end

  def test_send_now_without_an_email_or_when_it_fails
    login(:view_customer_appointments, :send_appointment_reminders)
    Customer.any_instance.stubs(:email).returns('')
    post "/customer_appointments/#{@appointment.id}/reminder"
    assert_equal I18n.t(:error_reminder_no_email), flash[:error]

    Customer.any_instance.stubs(:email).returns('jane@example.com')
    AppointmentReminderMailer.any_instance.stubs(:reminder).raises(Net::ReadTimeout)
    post "/customer_appointments/#{@appointment.id}/reminder"
    assert_match(/Net::ReadTimeout/, flash[:error])
  end

  def test_the_appointment_page_shows_the_reminder
    login(:view_customer_appointments, :send_appointment_reminders)
    get "/customer_appointments/#{@appointment.id}"
    assert_response :success
    assert_select '.appointment-reminder-scheduled', text: /jane@example\.com/
    assert_select 'form.appointment-reminder-send[action=?]', "/customer_appointments/#{@appointment.id}/reminder"

    AppointmentReminder.create!(customer_appointment: @appointment, appointment_date: @appointment.date, email: 'jane@example.com',
                                status: 'sent', attempts: 1, sent_at: Time.now, sent_by: User.find(2))
    get "/customer_appointments/#{@appointment.id}"
    assert_select '.appointment-reminder-sent', text: /John Smith/
    assert_select 'form.appointment-reminder-send button[data-confirm], form.appointment-reminder-send input[data-confirm]'
  end

  def test_no_send_button_without_permission_or_on_call_outs
    login(:view_customer_appointments)
    get "/customer_appointments/#{@appointment.id}"
    assert_select '.appointment-reminder'
    assert_select 'form.appointment-reminder-send', 0

    call_out = CustomerAppointment.create!(event_type: 'call_out', date: APPOINTMENT_AT, user_id: 3, duration: 1)
    get "/customer_appointments/#{call_out.id}"
    assert_response :success
    assert_select '.appointment-reminder', 0
  end

  # ---- a customer's reminders ----

  def test_turning_a_customers_reminders_off_and_on
    login(:manage_customer_reminders)
    post "/customers/#{@customer.id}/reminders/off"
    assert_redirected_to "/customers/#{@customer.id}"
    reminder_off = ReminderOptOut.find_by(customer_id: @customer.id)
    assert_equal User.find(2), reminder_off.user
    post "/customers/#{@customer.id}/reminders/off"
    assert_equal 1, ReminderOptOut.count

    post "/customers/#{@customer.id}/reminders/on", params: { back_url: '/customer_appointments' }
    assert_redirected_to '/customer_appointments'
    assert_not ReminderOptOut.opted_out?(@customer)

    post '/customers/424242/reminders/off'
    assert_response :not_found
  end

  def test_turning_reminders_off_needs_permission
    login(:view_customer_appointments)
    post "/customers/#{@customer.id}/reminders/off"
    assert_response :forbidden
    assert_not ReminderOptOut.opted_out?(@customer)
  end

  def test_the_customer_page
    install_fake_quickbooks
    Role.find(1).add_permission!(:view_customers)
    login(:view_customer_appointments, :manage_customer_reminders)
    get "/customers/#{@customer.id}"
    assert_response :success
    assert_select '.customer-reminders form[action=?]', "/customers/#{@customer.id}/reminders/off"

    ReminderOptOut.create!(customer_id: @customer.id)
    login(:view_customer_appointments)
    get "/customers/#{@customer.id}"
    assert_select '.customer-reminders', text: /#{Regexp.escape(I18n.t(:text_customer_reminders_off))}/
    assert_select '.customer-reminders form', 0
  end

  # ---- the settings page ----

  def test_test_email_and_run_are_for_admins
    login(:send_appointment_reminders, :manage_customer_reminders)
    post '/appointment_reminders/test'
    assert_response :forbidden
    post '/appointment_reminders/run'
    assert_response :forbidden
  end

  def test_a_test_email_with_unsaved_settings
    log_user('admin', 'admin')
    post '/appointment_reminders/test', params: { email: 'owner@example.com', settings: { shop_name: 'Unsaved Garage' } }
    assert_redirected_to '/settings/plugin/redmine_qbo_reminders'
    assert_equal I18n.t(:notice_reminder_test_sent, email: 'owner@example.com'), flash[:notice]
    mail = ActionMailer::Base.deliveries.last
    assert_equal ['owner@example.com'], mail.to
    assert_includes mail.text_part.body.to_s, 'Unsaved Garage'
    assert_includes mail.text_part.body.to_s, 'Hi Jane,'
  end

  def test_a_test_email_that_fails
    log_user('admin', 'admin')
    ActionMailer::Base.stubs(:perform_deliveries).returns(false)
    post '/appointment_reminders/test'
    assert_redirected_to '/settings/plugin/redmine_qbo_reminders'
    assert_match(/DeliveryOff/, flash[:error])
  end

  def test_run_from_the_settings_page
    log_user('admin', 'admin')
    travel_to(SEND_AT + 30.minutes)
    post '/appointment_reminders/run'
    assert_equal I18n.t(:notice_reminders_run, result: '1 sent, 0 failed, 0 skipped'), flash[:notice]

    set_reminder_settings('enabled' => '0')
    post '/appointment_reminders/run'
    assert_equal I18n.t(:error_reminders_disabled), flash[:error]
  end

  def test_settings_page
    log_user('admin', 'admin')
    get '/settings/plugin/redmine_qbo_reminders'
    assert_response :success
  end

  def test_page_loads_start_a_run
    RedmineQboReminders.instance_variable_set(:@last_check, nil)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    set_reminder_settings('check_on_page_loads' => '1')
    login
    assert_enqueued_with(job: AppointmentRemindersJob) { get '/my/page' }
  ensure
    RedmineQboReminders.instance_variable_set(:@last_check, nil)
  end
end
