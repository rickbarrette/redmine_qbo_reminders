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

class ReminderStatusTest < ActiveSupport::TestCase
  include QboRemindersTestHelper

  def status(appointment, now: Time.utc(2026, 11, 20, 12))
    RedmineQboReminders::ReminderStatus.for(appointment, now: now)
  end

  def reminder_for(appointment, **attributes)
    AppointmentReminder.create!({ customer_appointment: appointment, appointment_date: appointment.date,
                                  email: 'jane@example.com', status: 'sent', attempts: 1 }.merge(attributes))
  end

  def test_scheduled
    rs = status(create_appointment)
    assert_equal :scheduled, rs.state
    assert_equal SEND_AT, rs.at
    assert_equal 'jane@example.com', rs.email
  end

  def test_sent_sending_failed_and_given_up
    appointment = create_appointment
    reminder = reminder_for(appointment, sent_at: Time.now)
    assert status(appointment).sent?

    reminder.update_columns(status: 'pending', updated_at: Time.now)
    assert_equal :sending, status(appointment).state
    reminder.update_columns(updated_at: Time.now - 1.hour)
    assert_equal :failed, status(appointment).state

    reminder.update_columns(status: 'failed', attempts: 1)
    assert_equal :failed, status(appointment).state
    reminder.update_columns(attempts: 3)
    assert_equal :given_up, status(appointment).state
    reminder.update_columns(attempts: 1)
    set_reminder_settings('enabled' => '0')
    assert_equal :given_up, status(appointment).state
  end

  def test_why_no_reminder_goes_out
    appointment = create_appointment
    assert_equal :status, status(create_appointment(status: 'Cancelled')).state
    assert_equal :no_customer, status(create_appointment(customer: nil, customer_id: nil)).state
    assert_equal :too_late, status(appointment, now: APPOINTMENT_AT - 1.hour).state

    ReminderOptOut.create!(customer_id: appointment.customer_id)
    assert_equal :opted_out, status(appointment).state
    ReminderOptOut.delete_all

    Customer.any_instance.stubs(:email).returns(nil)
    assert_equal :no_email, status(appointment).state

    set_reminder_settings('enabled' => '0')
    assert_equal :off, status(appointment).state
  end
end
