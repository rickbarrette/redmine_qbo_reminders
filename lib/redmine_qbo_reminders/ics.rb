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
  # A calendar file (iCalendar) for the appointment, attached to the reminder so the customer can add it
  # to their calendar with a tap. Published, not an invitation, so mail apps don't ask them to RSVP.
  module Ics
    module_function

    # starts_at: a Time; minutes: how long the event is
    def build(uid:, starts_at:, summary:, minutes: 60, location: nil, description: nil, now: Time.now)
      fmt = ->(t) { t.utc.strftime('%Y%m%dT%H%M%SZ') }
      lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//redmine_qbo_reminders//EN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'BEGIN:VEVENT',
        "UID:#{uid}",
        "DTSTAMP:#{fmt.call(now)}",
        "DTSTART:#{fmt.call(starts_at)}",
        "DTEND:#{fmt.call(starts_at + minutes * 60)}",
        "SUMMARY:#{escape(summary)}"
      ]
      lines << "LOCATION:#{escape(location)}" if location.to_s.strip != ''
      lines << "DESCRIPTION:#{escape(description)}" if description.to_s.strip != ''
      lines += ['END:VEVENT', 'END:VCALENDAR']
      lines.map { |line| fold(line) }.join("\r\n") + "\r\n"
    end

    def escape(text)
      text.to_s.strip.gsub('\\', '\\\\\\\\').gsub(/\r?\n/, '\\n').gsub(',', '\\,').gsub(';', '\\;')
    end

    # Lines longer than 75 bytes continue on the next line, which starts with a space
    def fold(line)
      parts = []
      current = +''
      line.each_char do |ch|
        limit = parts.empty? ? 75 : 74
        if (current + ch).bytesize > limit
          parts << current
          current = +''
        end
        current << ch
      end
      parts << current
      parts.join("\r\n ")
    end
  end
end
