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

class ScheduleAndTemplateTest < ActiveSupport::TestCase
  include QboRemindersTestHelper

  def schedule(**options)
    RedmineQboReminders::Schedule.new(zone: ActiveSupport::TimeZone['Eastern Time (US & Canada)'], **options)
  end

  def eastern(*args)
    ActiveSupport::TimeZone['Eastern Time (US & Canada)'].local(*args)
  end

  # ---- schedule ----

  def test_send_time
    assert_equal eastern(2026, 11, 23, 16), schedule.send_time(eastern(2026, 11, 24, 9))
    assert_equal eastern(2026, 11, 21, 9, 30), schedule(days_before: 3, send_at: '9:30').send_time(eastern(2026, 11, 24, 9))
    assert_equal eastern(2026, 11, 24, 16), schedule(days_before: -2).send_time(eastern(2026, 11, 24, 9))
  end

  def test_the_appointment_time_is_the_time_entered
    assert_equal eastern(2026, 11, 24, 9), schedule.appointment_time(Time.utc(2026, 11, 24, 9))
  end

  def test_due
    at = eastern(2026, 11, 24, 9)
    assert_not schedule.due?(at, eastern(2026, 11, 23, 15, 59))
    assert schedule.due?(at, eastern(2026, 11, 23, 16))
    # Outside the sending window
    assert_not schedule.due?(at, eastern(2026, 11, 23, 20, 0))
    assert schedule.due?(at, eastern(2026, 11, 23, 19, 59))
    # Too close to the appointment
    assert_not schedule.due?(at, eastern(2026, 11, 24, 7, 30))
    assert schedule.too_late?(at, eastern(2026, 11, 24, 7))
  end

  def test_next_send
    at = eastern(2026, 11, 24, 9)
    assert_equal eastern(2026, 11, 23, 16), schedule.next_send(at, eastern(2026, 11, 20, 10))
    # Booked after the send time, late in the evening: the next window's start
    assert_equal eastern(2026, 11, 24, 8), schedule(min_lead_hours: 0.5).next_send(at, eastern(2026, 11, 23, 21))
    # Booked in the early morning: when the window opens
    assert_equal eastern(2026, 11, 23, 8), schedule(send_at: '06:00').next_send(at, eastern(2026, 11, 23, 5))
    # The window opens too close to the appointment
    assert_nil schedule.next_send(at, eastern(2026, 11, 23, 21))
  end

  def test_bad_times_fall_back_to_the_defaults
    s = schedule(send_at: '25:00', window_start: 'eight', window_end: '20:99', min_lead_hours: -1)
    assert_equal 16 * 60, s.send_at
    assert_equal 8 * 60, s.window_start
    assert_equal 20 * 60, s.window_end
    assert_equal 0, s.min_lead_hours
  end

  def test_lookahead
    now = Time.utc(2026, 11, 20, 12)
    assert_equal [now - 1.day, now + 3.days], schedule.lookahead(now)
  end

  # ---- template ----

  def test_placeholders_and_sections
    template = 'Hi {{first_name}}{{#vehicle}}, your {{vehicle}}{{/vehicle}}{{^vehicle}}, no vehicle{{/vehicle}}.'
    assert_equal 'Hi Jane, your 2022 Jeep Gladiator.',
                 RedmineQboReminders::Template.render(template, first_name: 'Jane', vehicle: ' 2022 Jeep Gladiator ')
    assert_equal 'Hi Jane, no vehicle.', RedmineQboReminders::Template.render(template, 'first_name' => 'Jane', 'vehicle' => nil)
    assert_equal 'Hi .', RedmineQboReminders::Template.render('Hi {{unknown}}.', {})
  end

  def test_empty_lines_collapse
    text = RedmineQboReminders::Template.render("Thanks,\n{{shop_name}}\n{{shop_address}}\n\n\n\n{{shop_phone}}", 'shop_name' => 'Example Garage')
    assert_equal "Thanks,\nExample Garage\n\n", text + "\n\n"
    assert_equal 'Your appointment Monday at 9:00 AM',
                 RedmineQboReminders::Template.render_line("Your appointment\n{{day}}  at {{time}}", 'day' => 'Monday', 'time' => '9:00 AM')
  end

  def test_the_default_body
    values = { 'first_name' => 'Jane', 'day' => 'Tuesday, November 24', 'time' => '9:00 AM', 'shop_name' => 'Example Garage' }
    body = RedmineQboReminders::Template.render(RedmineQboReminders::Template::DEFAULT_BODY, values)
    assert_includes body, 'appointment at Example Garage on Tuesday, November 24 at 9:00 AM.'
    assert_includes body, 'or to let us know if you need to reschedule.'
    assert_not_includes body, '{{'
  end

  def test_html
    html = RedmineQboReminders::Template.html("Hi <Jane>,\nline two\n\nSecond", "Footer")
    assert_includes html, '<p style="margin:0 0 1em">Hi &lt;Jane&gt;,<br>line two</p>'
    assert_includes html, '<p style="margin:0 0 1em">Second</p>'
    assert_includes html, '<hr'
    assert_includes html, 'color:#777">Footer</p>'
    assert_not_includes RedmineQboReminders::Template.html('Hi'), '<hr'
  end

  # ---- calendar file ----

  def test_calendar_file
    ics = RedmineQboReminders::Ics.build(uid: 'appointment-1@example.com', starts_at: Time.utc(2026, 11, 24, 14),
                                         summary: 'Appointment at Example Garage, Inc; bay 2', minutes: 90,
                                         location: "1 Main St\nSpringfield", now: Time.utc(2026, 11, 20, 12))
    lines = ics.split("\r\n")
    assert_equal 'BEGIN:VCALENDAR', lines.first
    assert_includes lines, 'METHOD:PUBLISH'
    assert_includes lines, 'DTSTART:20261124T140000Z'
    assert_includes lines, 'DTEND:20261124T153000Z'
    assert_includes lines, 'DTSTAMP:20261120T120000Z'
    assert_includes lines, 'SUMMARY:Appointment at Example Garage\\, Inc\; bay 2'
    assert_includes lines, 'LOCATION:1 Main St\\nSpringfield'
    assert_not(lines.any? { |l| l.start_with?('DESCRIPTION') })
    assert ics.end_with?("END:VCALENDAR\r\n")
  end

  def test_long_lines_are_folded
    ics = RedmineQboReminders::Ics.build(uid: 'u', starts_at: Time.utc(2026, 11, 24, 14), summary: 'é' * 60)
    summary = ics.split("\r\n").drop_while { |l| !l.start_with?('SUMMARY') }.take_while { |l| !l.start_with?('END') }
    assert summary.size > 1
    assert(summary.all? { |l| l.bytesize <= 75 })
    assert(summary.drop(1).all? { |l| l.start_with?(' ') })
    assert_equal 'SUMMARY:' + ('é' * 60), summary.first + summary.drop(1).map { |l| l[1..] }.join
  end
end
