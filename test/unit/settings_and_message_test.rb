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

class SettingsAndMessageTest < ActiveSupport::TestCase
  include QboRemindersTestHelper

  def test_defaults
    s = RedmineQboReminders::Settings.new(nil)
    assert_not s.enabled?
    assert s.check_on_page_loads?
    assert s.attach_calendar?
    assert_equal 'Eastern Time (US & Canada)', s.zone.name
    assert_equal ['Scheduled'], s.statuses
    assert_equal :smtp, s.delivery_options[:delivery_method]
  end

  def test_statuses
    s = settings('statuses' => ['Scheduled', 'Ready', ''])
    assert s.remind_status?('Ready')
    assert s.remind_status?('')
    assert_not s.remind_status?('Cancelled')
    assert_not settings('statuses' => ['Ready']).remind_status?(nil)
  end

  def test_unknown_time_zone
    assert_equal 'Eastern Time (US & Canada)', settings('time_zone' => 'Mars').zone.name
  end

  def test_from
    assert_equal 'Example Garage <shop@example.com>', settings.from
    assert_equal '"Smith, Jones & Co." <shop@example.com>', settings('from_name' => 'Smith, Jones & Co.').from
    assert_equal 'Shop <a@example.com>', settings('from_address' => 'Shop <a@example.com>').from
    assert_equal 'shop@example.com', settings('shop_name' => '').from
    with_settings mail_from: 'redmine@example.net' do
      assert_equal 'Example Garage <redmine@example.net>', settings('from_address' => ' ').from
    end
  end

  def test_reply_to_and_mail_domain
    assert_nil settings.reply_to
    assert_equal 'office@example.com', settings('reply_to' => ' office@example.com ').reply_to
    assert_equal 'example.com', settings.mail_domain
    assert_equal 'mail.example.org', settings('smtp_domain' => 'mail.example.org').mail_domain
  end

  def test_delivery_options
    assert_equal({}, settings.delivery_options)
    options = settings('delivery' => 'smtp', 'smtp_address' => '', 'smtp_port' => '').delivery_options
    assert_equal :smtp, options[:delivery_method]
    assert_equal({ address: 'smtp-relay.gmail.com', port: 587, domain: 'example.com', enable_starttls_auto: true,
                   open_timeout: 15, read_timeout: 30 }, options[:delivery_method_options])
    options = settings('delivery' => 'smtp', 'smtp_user_name' => ' shop ', 'smtp_password' => 'pw').delivery_options
    assert_equal ['shop', 'pw', :plain], options[:delivery_method_options].values_at(:user_name, :password, :authentication)
  end

  def reminder_message(appointment = create_appointment, settings: self.settings, **options)
    RedmineQboReminders::Message.for(appointment, settings, **options)
  end

  def test_message_values
    m = reminder_message
    assert_equal 'Jane', m.values['first_name']
    assert_equal 'Jane Customer', m.values['customer']
    assert_equal 'Tuesday, November 24', m.values['day']
    assert_equal '11/24/2026', m.values['date']
    assert_equal '9:00 AM', m.values['time']
    assert_equal 'Example Garage', m.values['shop_name']
    assert_equal "appointment-#{CustomerAppointment.last.id}@example.com", m.uid
    assert_equal 'Jen', reminder_message(first_name: 'Jen').values['first_name']
  end

  def test_message_text
    m = reminder_message(settings: settings('subject' => '{{shop_name}}: {{day}}', 'body' => 'Hi {{first_name}}', 'footer' => 'Reply STOP'))
    assert_equal 'Example Garage: Tuesday, November 24', m.subject
    assert_equal "Hi Jane\n\n--\nReply STOP", m.text
    assert_includes m.html, 'Reply STOP'
    m = reminder_message(settings: settings('footer' => ''))
    assert_nil m.footer
    assert_equal m.body, m.text
    assert_equal 'Reminder: your appointment Tuesday, November 24 at 9:00 AM', m.subject
  end

  def test_message_calendar_file
    ics = reminder_message.ics
    assert_includes ics, 'SUMMARY:Appointment at Example Garage'
    assert_includes ics, 'DTSTART:20261124T090000Z'
    assert_includes ics, 'LOCATION:1 Main St\\, Springfield'
    assert_includes ics, 'DESCRIPTION:Questions or need to reschedule? Call 401-555-0100'
    assert_nil reminder_message(settings: settings('attach_calendar' => '0')).ics
    assert_includes reminder_message(settings: settings('shop_name' => '')).ics, "SUMMARY:Appointment\r\n"
  end

  def test_the_email
    m = reminder_message(settings: settings('reply_to' => 'office@example.com'))
    mail = AppointmentReminderMailer.reminder(m, 'jane@example.com')
    assert_equal ['jane@example.com'], mail.to
    assert_equal ['shop@example.com'], mail.from
    assert_equal ['office@example.com'], mail.reply_to
    assert_equal m.subject, mail.subject
    assert_match(/\Areminder\.\d+\.\h+@example\.com\z/, mail.message_id)
    assert_equal ['appointment.ics'], mail.attachments.map(&:filename)
    assert_includes mail.text_part.body.to_s, 'Hi Jane,'
    assert_includes mail.html_part.body.to_s, '<p style='
  end

  def test_the_email_through_the_plugins_smtp_server
    mail = AppointmentReminderMailer.reminder(reminder_message, 'jane@example.com', settings: settings('delivery' => 'smtp'))
    assert_equal :smtp, mail.delivery_method.class.name.demodulize.underscore.sub('_delivery', '').to_sym
    assert_equal 'smtp-relay.gmail.com', mail.delivery_method.settings[:address]
    assert mail.perform_deliveries
  end

  def test_the_email_when_redmine_delivery_is_off
    ActionMailer::Base.stubs(:perform_deliveries).returns(false)
    assert_raises(AppointmentReminderMailer::DeliveryOff) do
      AppointmentReminderMailer.reminder(reminder_message, 'jane@example.com').message
    end
  end

  # ---- redmine_qbo's customer emails ----

  def test_redmine_qbo_mail_settings
    hook = RedmineQboReminders::Hooks::MailHookListener.instance
    set_reminder_settings('reply_to' => 'office@example.com')
    assert_equal({ shop_name: 'Example Garage', from: 'Example Garage <shop@example.com>', reply_to: 'office@example.com',
                   delivery: nil }, hook.qbo_mail_settings)
    set_reminder_settings('delivery' => 'smtp')
    assert_equal :smtp, hook.qbo_mail_settings[:delivery][:delivery_method]
    assert_equal 'Example Garage', RedmineQboBilling.mail_settings[:shop_name]
  end
end
