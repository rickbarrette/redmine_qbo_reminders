#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Redmine::Plugin.register :redmine_qbo_reminders do

  # About
  name 'Redmine QBO Reminders plugin'
  author 'Rick Barrette'
  description 'Emails customers reminders of their appointments (redmine_qbo_calendar), using their email address in QuickBooks Online'
  version '2026.11.0'
  url 'https://github.com/rickbarrette/redmine_qbo_reminders'
  author_url 'https://barrettefabrication.com'
  requires_redmine version_or_higher: '7.0.0'

  # Appointments live in redmine_qbo_calendar; customers and their email addresses in redmine_qbo
  begin
    requires_redmine_plugin :redmine_qbo_calendar, version_or_higher: '2026.11.0'
  rescue Redmine::PluginNotFound
    raise 'Please install the redmine_qbo_calendar plugin (https://github.com/rickbarrette/redmine_qbo_calendar)'
  end

  settings default: RedmineQboReminders::Settings::DEFAULTS.dup, partial: 'settings/appointment_reminders'

  # Sending a reminder from the appointment page, and turning reminders on or off for a customer
  permission :send_appointment_reminders, { appointment_reminders: [:send_now, :opt_out, :opt_in] }, global: true
end

RedmineQboReminders.setup
