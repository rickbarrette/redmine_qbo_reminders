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
  # Emails the reminders that are due. Run by the rake task (cron), and on page loads every few minutes when
  # that's turned on. Safe to run often and from several places at once: each reminder is claimed in the
  # database before it's sent, so a customer never gets two for the same appointment time.
  class Sender
    Result = Struct.new(:sent, :failed, :skipped) do
      def to_s
        "#{sent} sent, #{failed} failed, #{skipped} skipped"
      end
    end

    attr_reader :settings, :now, :result

    def self.run(now: Time.now)
      new(now: now).run
    end

    def initialize(settings: Settings.current, now: Time.now)
      @settings = settings
      @now = now
      @result = Result.new(0, 0, 0)
    end

    def run
      return result unless settings.enabled?
      schedule = settings.schedule
      return result unless schedule.in_window?(now)

      from, to = schedule.lookahead(now)
      CustomerAppointment.where(date: from..to).includes(:customer).find_each do |appointment|
        consider(appointment, schedule)
      end
      log "Run finished: #{result}" if result.sent + result.failed > 0
      result
    end

    # Sends an appointment's reminder now, whatever the schedule says (the appointment page's button).
    # Returns the AppointmentReminder, or nil when the customer has no email address.
    def send_now(appointment, user: nil)
      email = self.class.customer_email(appointment.customer)
      return nil if email.nil?
      existing = AppointmentReminder.find_by(customer_appointment_id: appointment.id, appointment_date: appointment.date)
      deliver(appointment, email, existing, user: user)
    end

    # The customer's email address in QuickBooks (the first, when there are several), or nil
    def self.customer_email(customer)
      return nil if customer.nil?
      address = customer.email.to_s.split(/[,;]/).map(&:strip).find { |a| a.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/) }
      address.presence
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboReminders] Could not read the email of customer #{customer&.id}: #{e.message}"
      nil
    end

    # The customer's first name in QuickBooks, falling back to the first word of their name
    def self.first_name(customer)
      customer.respond_to?(:given_name) ? customer.given_name.to_s.strip.presence : nil
    rescue StandardError
      nil
    end

    private

    def consider(appointment, schedule)
      at = schedule.appointment_time(appointment.date)
      return unless settings.remind_status?(appointment.status) && schedule.due?(at, now)

      customer = appointment.customer
      return skip(appointment, 'no customer') if customer.nil?
      return skip(appointment, 'customer turned reminders off') if ReminderOptOut.opted_out?(customer)

      existing = AppointmentReminder.find_by(customer_appointment_id: appointment.id, appointment_date: appointment.date)
      return if existing && !existing.retry?

      email = self.class.customer_email(customer)
      return skip(appointment, 'customer has no email address') if email.nil?

      deliver(appointment, email, existing)
    end

    def deliver(appointment, email, existing, user: nil)
      reminder = claim(appointment, email, existing)
      return nil if reminder.nil?

      message = Message.for(appointment, settings, first_name: self.class.first_name(appointment.customer))
      AppointmentReminderMailer.reminder(message, email).deliver_now
      reminder.update!(status: 'sent', sent_at: Time.now, sent_by: user, error: nil)
      result.sent += 1
      log "Sent the reminder for appointment ##{appointment.id} to #{email}"
      reminder
    rescue StandardError => e
      result.failed += 1
      log "Could not send the reminder for appointment ##{appointment.id} to #{email}: #{e.class}: #{e.message}"
      reminder&.update_columns(status: 'failed', error: "#{e.class}: #{e.message}".truncate(1000), updated_at: Time.now)
      reminder
    end

    # Marks the reminder as being sent, or nil when another run got to it first
    def claim(appointment, email, existing)
      if existing.nil?
        AppointmentReminder.create!(customer_appointment: appointment, appointment_date: appointment.date,
                                    email: email, status: 'pending', attempts: 1)
      else
        claimed = AppointmentReminder.where(id: existing.id, attempts: existing.attempts)
                                     .update_all(status: 'pending', attempts: existing.attempts + 1, email: email,
                                                 error: nil, updated_at: Time.now)
        claimed.zero? ? nil : existing.reload
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def skip(appointment, reason)
      result.skipped += 1
      log "Skipped appointment ##{appointment.id}: #{reason}"
      nil
    end

    def log(msg)
      Rails.logger.info "[RedmineQboReminders] #{msg}"
    end
  end
end
