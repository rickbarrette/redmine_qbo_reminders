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
  # The plugin's settings (Administration » Plugins » Configure), with defaults
  class Settings
    DEFAULTS = {
      'enabled' => '0',
      'from_name' => '',
      'from_address' => '',
      'reply_to' => '',
      # 'redmine': Redmine's own email settings (config/configuration.yml); 'smtp': the server below
      'delivery' => 'smtp',
      'smtp_address' => 'smtp-relay.gmail.com',
      'smtp_port' => '587',
      'smtp_domain' => '',
      'smtp_user_name' => '',
      'smtp_password' => '',
      'time_zone' => 'Eastern Time (US & Canada)',
      'days_before' => '1',
      'send_at' => '16:00',
      'window_start' => '08:00',
      'window_end' => '20:00',
      'min_lead_hours' => '2',
      'statuses' => ['Scheduled'],
      'check_on_page_loads' => '1',
      'attach_calendar' => '1',
      'shop_name' => '',
      'shop_phone' => '',
      'shop_address' => '',
      'subject' => Template::DEFAULT_SUBJECT,
      'body' => Template::DEFAULT_BODY
    }.freeze

    def self.current
      new(Setting.plugin_redmine_qbo_reminders)
    end

    def initialize(values = {})
      @values = DEFAULTS.merge((values || {}).to_h.transform_keys(&:to_s).reject { |_, v| v.nil? })
    end

    def [](key)
      @values[key.to_s]
    end

    def enabled?
      self['enabled'].to_s == '1'
    end

    def check_on_page_loads?
      self['check_on_page_loads'].to_s == '1'
    end

    def attach_calendar?
      self['attach_calendar'].to_s == '1'
    end

    # Appointment statuses that get reminders; a blank status counts as Scheduled (the form's first choice)
    def statuses
      Array(self['statuses']).map(&:to_s).reject(&:empty?)
    end

    def remind_status?(status)
      statuses.include?(status.to_s.presence || 'Scheduled')
    end

    def zone
      ActiveSupport::TimeZone[self['time_zone'].to_s] || ActiveSupport::TimeZone['Eastern Time (US & Canada)']
    end

    def schedule
      Schedule.new(zone: zone, days_before: self['days_before'], send_at: self['send_at'],
                   window_start: self['window_start'], window_end: self['window_end'],
                   min_lead_hours: self['min_lead_hours'])
    end

    def from_address
      self['from_address'].to_s.strip.presence || (defined?(Setting) && Setting.respond_to?(:mail_from) ? Setting.mail_from.to_s : '')
    end

    # "Ocean State Off Road <sales@example.com>", quoting the name when it needs it
    def from
      address = from_address
      name = self['from_name'].to_s.strip.presence || self['shop_name'].to_s.strip.presence
      return address if name.nil? || address.include?('<')
      name = %("#{name.gsub(/(["\\])/, '\\\\\1')}") if name =~ /[()<>\[\]:;@\\,."]/
      "#{name} <#{address}>"
    end

    def reply_to
      self['reply_to'].to_s.strip.presence
    end

    # The domain mail is sent from (sales@example.com -> example.com): the SMTP greeting and Message-IDs
    def mail_domain
      self['smtp_domain'].to_s.strip.presence || from_address[/@([^>\s]+)/, 1] || 'localhost'
    end

    # Options for ActionMailer's mail(): empty to use Redmine's email settings
    def delivery_options
      return {} unless self['delivery'] == 'smtp'
      smtp = {
        address: self['smtp_address'].to_s.strip.presence || 'smtp-relay.gmail.com',
        port: (self['smtp_port'].presence || 587).to_i,
        domain: mail_domain,
        enable_starttls_auto: true,
        open_timeout: 15,
        read_timeout: 30
      }
      if self['smtp_user_name'].to_s.strip != ''
        smtp.merge!(user_name: self['smtp_user_name'].to_s.strip, password: self['smtp_password'].to_s, authentication: :plain)
      end
      { delivery_method: :smtp, delivery_method_options: smtp }
    end

    # Shop details for the message
    def shop_values
      { 'shop_name' => self['shop_name'], 'shop_phone' => self['shop_phone'], 'shop_address' => self['shop_address'] }
    end
  end
end
