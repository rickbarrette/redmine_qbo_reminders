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
  # When an appointment's reminder goes out. Times are the shop's wall-clock time (the time zone set in the
  # plugin's settings), the way appointments are entered and shown.
  #
  # A reminder is due once its send time has passed (days_before days ahead of the appointment, at send_at),
  # while the appointment is still more than min_lead_hours away, and only between window_start and
  # window_end, so a late run never emails customers in the middle of the night.
  class Schedule
    attr_reader :zone, :days_before, :send_at, :window_start, :window_end, :min_lead_hours

    def initialize(zone:, days_before: 1, send_at: '16:00', window_start: '08:00', window_end: '20:00', min_lead_hours: 2)
      @zone = zone
      @days_before = [days_before.to_i, 0].max
      @send_at = minutes(send_at, 16 * 60)
      @window_start = minutes(window_start, 8 * 60)
      @window_end = minutes(window_end, 20 * 60)
      @min_lead_hours = [min_lead_hours.to_f, 0].max
    end

    # The appointment's time (stored as the time entered) as a time in the shop's zone
    def appointment_time(datetime)
      zone.local(datetime.year, datetime.month, datetime.day, datetime.hour, datetime.min)
    end

    # When the reminder for an appointment at this (shop) time goes out
    def send_time(appointment_at)
      day = appointment_at.to_date - days_before
      zone.local(day.year, day.month, day.day, send_at / 60, send_at % 60)
    end

    # Too close to the appointment to bother (or already past)
    def too_late?(appointment_at, now)
      now >= appointment_at - (min_lead_hours * 3600)
    end

    def in_window?(now)
      local = now.in_time_zone(zone)
      m = local.hour * 60 + local.min
      m >= window_start && m < window_end
    end

    def due?(appointment_at, now)
      now >= send_time(appointment_at) && !too_late?(appointment_at, now) && in_window?(now)
    end

    # When a not-yet-due reminder will go out: its send time, moved to the next sending window if it falls
    # outside one. nil when it's too late to send.
    def next_send(appointment_at, now)
      at = [send_time(appointment_at), now].max.in_time_zone(zone)
      unless in_window?(at)
        m = at.hour * 60 + at.min
        day = m >= window_end ? at.to_date + 1 : at.to_date
        at = zone.local(day.year, day.month, day.day, window_start / 60, window_start % 60)
      end
      too_late?(appointment_at, at) ? nil : at
    end

    # Appointments worth looking at now: a little either side of the reminder lead, wide enough to cover
    # the difference between the server's and the shop's time zone
    def lookahead(now)
      [now - 1.day, now + (days_before + 2).days]
    end

    private

    # "16:30" -> 990
    def minutes(value, default)
      h, m = value.to_s.split(':', 2).map { |v| Integer(v, 10) }
      return default if h.nil? || h.negative? || h > 23 || m.to_i.negative? || m.to_i > 59
      h * 60 + m.to_i
    rescue ArgumentError, TypeError
      default
    end
  end
end
