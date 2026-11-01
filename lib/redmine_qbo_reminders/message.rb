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
  # One reminder: who it's to and what it says, built from an appointment and the settings
  class Message
    attr_reader :settings, :values, :starts_at, :uid

    # values: the placeholders' values (see Template); starts_at: the appointment's time in the shop's zone
    def initialize(settings:, values:, starts_at:, uid:)
      @settings = settings
      @values = settings.shop_values.merge(values.transform_keys(&:to_s))
      @starts_at = starts_at
      @uid = uid
    end

    # Built from an appointment (redmine_qbo_calendar's CustomerAppointment)
    def self.for(appointment, settings, customer_name: nil, first_name: nil)
      starts_at = settings.schedule.appointment_time(appointment.date)
      customer = appointment.customer
      name = customer_name || customer&.name.to_s
      values = {
        'customer' => name,
        'first_name' => first_name.presence || name.split(/\s+/).first.to_s,
        'vehicle' => appointment.respond_to?(:vehicle) ? appointment.vehicle&.to_s : nil,
        'subject' => appointment.subject
      }.merge(when_values(starts_at))
      new(settings: settings, values: values, starts_at: starts_at,
          uid: "appointment-#{appointment.id}@#{settings.mail_domain}")
    end

    # {{day}} "Monday, November 2", {{date}} "11/02/2026", {{time}} "9:00 AM"
    def self.when_values(starts_at)
      {
        'day' => starts_at.strftime('%A, %B %-d'),
        'date' => starts_at.strftime('%m/%d/%Y'),
        'time' => starts_at.strftime('%-l:%M %p')
      }
    end

    def subject
      Template.render_line(settings['subject'].presence || Template::DEFAULT_SUBJECT, values)
    end

    # The message and its footer, as plain text
    def text
      [body, footer].compact.join("\n\n--\n")
    end

    def html
      Template.html(body, footer)
    end

    def body
      Template.render(settings['body'].presence || Template::DEFAULT_BODY, values)
    end

    # nil when the footer setting is blank
    def footer
      Template.render(settings['footer'].to_s, values).presence
    end

    # The calendar attachment, or nil when it's turned off
    def ics
      return nil unless settings.attach_calendar?
      shop = values['shop_name'].to_s.strip
      summary = shop.empty? ? 'Appointment' : "Appointment at #{shop}"
      summary += " – #{values['vehicle']}" if values['vehicle'].to_s.strip != ''
      Ics.build(uid: uid, starts_at: starts_at, summary: summary, location: values['shop_address'],
                description: values['shop_phone'].to_s.strip.empty? ? nil : "Questions or need to reschedule? Call #{values['shop_phone']}")
    end
  end
end
