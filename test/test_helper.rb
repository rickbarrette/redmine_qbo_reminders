#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../../../test/test_helper', __dir__)

module QboRemindersTestHelper
  PERMISSIONS = %i[view_customer_appointments send_appointment_reminders manage_customer_reminders].freeze

  # Tuesday 2026-11-24, 9am: the appointment. With these settings its reminder goes out Monday at 4pm.
  APPOINTMENT_AT = Time.utc(2026, 11, 24, 9)
  SEND_AT = Time.utc(2026, 11, 23, 16)

  # Mail goes through Redmine's own (test) delivery, never an SMTP server; times are UTC to keep them simple
  SETTINGS = { 'enabled' => '1', 'delivery' => 'redmine', 'time_zone' => 'UTC', 'from_address' => 'shop@example.com',
               'shop_name' => 'Example Garage', 'shop_phone' => '401-555-0100', 'shop_address' => '1 Main St, Springfield',
               'check_on_page_loads' => '0' }.freeze

  def self.included(base)
    base.include ActiveSupport::Testing::TimeHelpers
    base.include ActiveJob::TestHelper
    base.fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
                  :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows
    base.setup do
      @saved_queue_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      AppointmentReminder.delete_all
      ReminderOptOut.delete_all
      CustomerAppointment.delete_all
      Customer.where(id: 9700..9799).delete_all
      Setting.plugin_redmine_qbo_reminders = SETTINGS.dup
      Setting.plugin_redmine_qbo_calendar = {}
      Role.find(1).remove_permission!(*PERMISSIONS)
      ActionMailer::Base.deliveries.clear
      # Customers' email addresses come from QuickBooks
      Customer.any_instance.stubs(:email).returns('jane@example.com')
      RedmineQboBilling::EstimateIssueBuilder.stubs(:labor_hours).returns(0)
    end
    base.teardown do
      travel_back
      ActiveJob::Base.queue_adapter = @saved_queue_adapter
    end
  end

  def settings(values = {})
    RedmineQboReminders::Settings.new(SETTINGS.merge(values))
  end

  def set_reminder_settings(values)
    Setting.plugin_redmine_qbo_reminders = SETTINGS.merge(values)
  end

  def allow(*permissions)
    role = Role.find(1)
    role.remove_permission!(*PERMISSIONS)
    permissions.each { |p| role.add_permission!(p) }
  end

  # A customer, without sending it to QuickBooks
  def create_customer(id = 9701, name = 'Jane Customer')
    customer = Customer.new(id: id, name: name)
    customer.skip_qbo_push = true
    customer.save!
    customer
  end

  def create_appointment(at: APPOINTMENT_AT, customer: nil, **attributes)
    customer ||= Customer.find_by(id: 9701) || create_customer
    CustomerAppointment.create!({ subject: 'Lift kit install', date: at, duration: 1, estimated_hours: 4,
                                  user_id: 2, project_id: 1, customer_id: customer&.id }.merge(attributes))
  end
end
