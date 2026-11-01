#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# A reminder emailed (or being emailed, or that failed) for an appointment at a given time
class AppointmentReminder < ActiveRecord::Base
  STATUSES = %w[pending sent failed].freeze
  # Tries before a failing reminder is given up on (it can still be sent from the appointment page)
  MAX_ATTEMPTS = 3
  # A "pending" row older than this was left by a run that died mid-send, and may be tried again
  STALE_AFTER = 30 * 60

  belongs_to :customer_appointment
  belongs_to :sent_by, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def sent?
    status == 'sent'
  end

  def failed?
    status == 'failed'
  end

  def stale?
    status == 'pending' && updated_at && updated_at < Time.now - STALE_AFTER
  end

  # Worth another try on schedule
  def retry?
    (failed? || stale?) && attempts < MAX_ATTEMPTS
  end
end
