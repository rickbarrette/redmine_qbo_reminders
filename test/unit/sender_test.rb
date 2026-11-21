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

class SenderTest < ActiveSupport::TestCase
  include QboRemindersTestHelper

  def run_at(now = SEND_AT + 30.minutes)
    RedmineQboReminders::Sender.run(now: now)
  end

  def test_sends_a_due_reminder_once
    appointment = create_appointment
    result = run_at
    assert_equal '1 sent, 0 failed, 0 skipped', result.to_s
    reminder = AppointmentReminder.find_by(customer_appointment_id: appointment.id)
    assert reminder.sent?
    assert_equal 'jane@example.com', reminder.email
    assert_equal 1, reminder.attempts
    assert_equal APPOINTMENT_AT, reminder.appointment_date
    mail = ActionMailer::Base.deliveries.last
    assert_equal ['jane@example.com'], mail.to

    assert_equal '0 sent, 0 failed, 0 skipped', run_at(SEND_AT + 1.hour).to_s
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  def test_a_moved_appointment_gets_another_reminder
    appointment = create_appointment
    run_at
    appointment.update!(date: APPOINTMENT_AT + 1.day)
    assert_equal 1, run_at(SEND_AT + 1.day + 30.minutes).sent
    assert_equal 2, AppointmentReminder.where(customer_appointment_id: appointment.id).count
  end

  def test_nothing_before_the_send_time_or_outside_the_window
    create_appointment
    assert_equal 0, run_at(SEND_AT - 1.minute).sent
    assert_equal 0, run_at(SEND_AT + 5.hours).sent # 9pm
    assert_equal 0, run_at(APPOINTMENT_AT - 90.minutes).sent # too close
    assert_empty ActionMailer::Base.deliveries
  end

  def test_nothing_when_turned_off
    create_appointment
    set_reminder_settings('enabled' => '0')
    assert_equal 0, run_at.sent
  end

  def test_skipped_appointments
    create_appointment(status: 'Cancelled')
    create_appointment(customer: nil, customer_id: nil, subject: 'Walk-in')
    off = create_appointment(customer: create_customer(9702, 'Bob Builder'))
    ReminderOptOut.create!(customer_id: off.customer_id)
    create_appointment(customer: create_customer(9703, 'No Email'))
    CustomerAppointment.create!(event_type: 'call_out', date: APPOINTMENT_AT, user_id: 3, duration: 1)
    Customer.any_instance.stubs(:email).returns('')
    result = run_at
    # The cancelled one and the call-out aren't considered; the others are skipped
    assert_equal '0 sent, 0 failed, 3 skipped', result.to_s
    assert_equal 0, AppointmentReminder.count
  end

  def test_other_statuses_from_the_settings
    create_appointment(status: 'Ready')
    assert_equal 0, run_at.sent
    set_reminder_settings('statuses' => ['Ready'])
    assert_equal 1, run_at.sent
  end

  def test_failures_are_recorded_and_retried
    appointment = create_appointment
    AppointmentReminderMailer.any_instance.stubs(:reminder).raises(Net::SMTPAuthenticationError.new('535 bad login'))
    assert_equal '0 sent, 1 failed, 0 skipped', run_at.to_s
    reminder = AppointmentReminder.find_by(customer_appointment_id: appointment.id)
    assert reminder.failed?
    assert_match(/Net::SMTPAuthenticationError: 535 bad login/, reminder.error)
    assert reminder.retry?

    run_at(SEND_AT + 40.minutes)
    run_at(SEND_AT + 50.minutes)
    assert_equal AppointmentReminder::MAX_ATTEMPTS, reminder.reload.attempts
    assert_not reminder.retry?
    assert_equal 0, run_at(SEND_AT + 60.minutes).failed

    AppointmentReminderMailer.any_instance.unstub(:reminder)
    assert_equal 0, run_at(SEND_AT + 70.minutes).sent
  end

  def test_a_run_that_died_mid_send_is_retried_later
    appointment = create_appointment
    reminder = AppointmentReminder.create!(customer_appointment: appointment, appointment_date: appointment.date,
                                           email: 'jane@example.com', status: 'pending', attempts: 1)
    assert_equal 0, run_at.sent
    reminder.update_columns(updated_at: Time.now - 31.minutes)
    assert reminder.reload.stale?
    assert_equal 1, run_at.sent
    assert_equal 2, reminder.reload.attempts
    assert reminder.sent?
  end

  def test_another_run_that_claimed_the_reminder_first_wins
    appointment = create_appointment
    existing = AppointmentReminder.create!(customer_appointment: appointment, appointment_date: appointment.date,
                                           email: 'jane@example.com', status: 'failed', attempts: 1)
    stale_copy = AppointmentReminder.find(existing.id)
    existing.update_columns(attempts: 2)
    sender = RedmineQboReminders::Sender.new
    assert_nil sender.send(:claim, appointment, 'jane@example.com', stale_copy)
  end

  def test_send_now_ignores_the_schedule
    appointment = create_appointment(status: 'Cancelled')
    reminder = RedmineQboReminders::Sender.new.send_now(appointment, user: User.find(2))
    assert reminder.sent?
    assert_equal User.find(2), reminder.sent_by
    again = RedmineQboReminders::Sender.new.send_now(appointment)
    assert_equal reminder.id, again.id
    assert_equal 2, again.attempts
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  def test_send_now_without_an_email_address
    Customer.any_instance.stubs(:email).returns(nil)
    assert_nil RedmineQboReminders::Sender.new.send_now(create_appointment)
  end

  def test_customer_email
    customer = create_customer
    Customer.any_instance.stubs(:email).returns('not an email; jane@example.com, bob@example.com')
    assert_equal 'jane@example.com', RedmineQboReminders::Sender.customer_email(customer)
    Customer.any_instance.stubs(:email).raises(StandardError, 'QuickBooks is down')
    assert_nil RedmineQboReminders::Sender.customer_email(customer)
    assert_nil RedmineQboReminders::Sender.customer_email(nil)
  end

  def test_runs_from_the_job
    create_appointment
    travel_to(SEND_AT + 30.minutes) { AppointmentRemindersJob.perform_now }
    assert_equal 1, AppointmentReminder.where(status: 'sent').count
  end

  def test_page_loads_start_a_run_now_and_then
    RedmineQboReminders.instance_variable_set(:@last_check, nil)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    assert_no_enqueued_jobs { RedmineQboReminders.check_soon }
    set_reminder_settings('check_on_page_loads' => '1')
    assert_enqueued_jobs(1, only: AppointmentRemindersJob) do
      RedmineQboReminders.check_soon
      RedmineQboReminders.check_soon
    end
    RedmineQboReminders.instance_variable_set(:@last_check, nil)
    # Another process ran it within the last few minutes
    assert_no_enqueued_jobs { RedmineQboReminders.check_soon }
  ensure
    RedmineQboReminders.instance_variable_set(:@last_check, nil)
  end

  def test_opt_outs_are_one_per_customer
    customer = create_customer
    assert_not ReminderOptOut.opted_out?(customer)
    ReminderOptOut.create!(customer_id: customer.id)
    assert ReminderOptOut.opted_out?(customer)
    assert_not ReminderOptOut.new(customer_id: customer.id).valid?
    assert_not ReminderOptOut.opted_out?(nil)
    assert_not AppointmentReminder.new(status: 'lost').valid?
  end
end
