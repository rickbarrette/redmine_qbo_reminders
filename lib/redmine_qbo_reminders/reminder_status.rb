#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboReminders
  # Where an appointment's reminder stands, for the appointment page:
  #   :sent       sent (reminder.sent_at, to email)
  #   :failed     the last try failed (reminder.error); :given_up when it won't be tried again on schedule
  #   :sending    being sent right now
  #   :scheduled  will go out at `at` to email
  #   :off        reminders are turned off in the plugin's settings
  #   :opted_out  turned off for this customer
  #   :status     the appointment's status doesn't get reminders (e.g. Cancelled)
  #   :no_customer, :no_email
  #   :too_late   too close to (or past) the appointment to send on schedule
  class ReminderStatus
    attr_reader :state, :at, :email, :reminder

    def self.for(appointment, settings: Settings.current, now: Time.now)
      new(appointment, settings, now)
    end

    def initialize(appointment, settings, now)
      @reminder = AppointmentReminder.find_by(customer_appointment_id: appointment.id, appointment_date: appointment.date)
      @state = compute(appointment, settings, now)
    end

    def sent?
      state == :sent
    end

    private

    def compute(appointment, settings, now)
      if reminder
        @email = reminder.email
        return :sent if reminder.sent?
        return :sending if reminder.status == 'pending' && !reminder.stale?
        return(reminder.retry? && settings.enabled? ? :failed : :given_up) if reminder.failed? || reminder.stale?
      end
      return :off unless settings.enabled?
      return :status unless settings.remind_status?(appointment.status)
      return :no_customer if appointment.customer.nil?
      return :opted_out if ReminderOptOut.opted_out?(appointment.customer)

      @email = Sender.customer_email(appointment.customer)
      return :no_email if @email.nil?

      schedule = settings.schedule
      @at = schedule.next_send(schedule.appointment_time(appointment.date), now)
      @at ? :scheduled : :too_late
    end
  end
end
