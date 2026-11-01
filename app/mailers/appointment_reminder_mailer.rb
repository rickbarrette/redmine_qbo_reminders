#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'securerandom'

# The reminder email: plain text and HTML, with the appointment as a calendar file. Sent through the SMTP
# server in the plugin's settings (e.g. Google Workspace's SMTP relay), or through Redmine's own email
# settings. Not Redmine's Mailer, which would add Redmine's From address, headers and footer.
class AppointmentReminderMailer < ActionMailer::Base
  layout false
  # So a refused message is recorded as failed (and retried), not as sent
  self.raise_delivery_errors = true

  # message: a RedmineQboReminders::Message
  def reminder(message, email, settings: message.settings)
    if (ics = message.ics)
      attachments['appointment.ics'] = { mime_type: 'text/calendar; method=PUBLISH; charset=UTF-8', content: ics }
    end
    # A Message-ID on the sending domain, rather than the server's host name
    headers['Message-ID'] = "<reminder.#{Time.now.to_i}.#{SecureRandom.hex(6)}@#{settings.mail_domain}>"

    delivery = settings.delivery_options
    # Through Redmine's own settings, Redmine decides whether mail goes out at all; say so rather than
    # quietly dropping the reminder
    if delivery.empty? && !ActionMailer::Base.perform_deliveries
      raise DeliveryOff, "Redmine's email delivery is turned off (config/configuration.yml); choose \"This SMTP server\" in the reminder settings"
    end

    options = { to: email, from: settings.from, subject: message.subject }
    options[:reply_to] = settings.reply_to if settings.reply_to
    mail(options.merge(delivery)) do |format|
      format.text { render plain: message.text }
      format.html { render html: message.html.html_safe }
    end
    # Redmine turns delivery off for every mailer when it has no email settings of its own (and in some
    # environments); reminders sent through the plugin's own SMTP server go out regardless
    message_obj = self.message
    message_obj.perform_deliveries = true unless delivery.empty?
    message_obj
  end

  class DeliveryOff < StandardError; end
end
