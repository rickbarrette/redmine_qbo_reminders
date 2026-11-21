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
  # How often page loads may start a run (when "Check on page loads" is on)
  CHECK_EVERY = 10 * 60

  def self.setup
    RedmineQboReminders::Hooks::ViewHookListener
    RedmineQboReminders::Hooks::AppointmentHookListener
    RedmineQboReminders::Hooks::CustomerHookListener
    RedmineQboReminders::Hooks::MailHookListener
  end

  # Starts a run in the background, at most every CHECK_EVERY seconds (page loads call this). Without cron,
  # reminders go out while someone is using Redmine.
  def self.check_soon
    settings = Settings.current
    return unless settings.enabled? && settings.check_on_page_loads?
    return if @last_check && Time.now - @last_check < CHECK_EVERY
    @last_check = Time.now
    # Shared between Redmine's processes when its cache is; the claim in Sender stops double sends anyway
    return unless Rails.cache.write('redmine_qbo_reminders:last_check', Time.now.to_i, unless_exist: true,
                                    expires_in: CHECK_EVERY)
    AppointmentRemindersJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[RedmineQboReminders] Could not start a run: #{e.message}"
  end
end
