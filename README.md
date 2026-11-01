# Redmine QBO Reminders

Emails customers a reminder before their appointments in [redmine_qbo_calendar](https://github.com/rickbarrette/redmine_qbo_calendar), at the email address on their QuickBooks Online customer ([redmine_qbo](https://github.com/rickbarrette/redmine_qbo)). The email comes from your own mailbox (for example sales@yourdomain.com through Google Workspace), so there's nothing extra to pay for, and customers can reply to confirm or reschedule.

* **When**: a set number of days before the appointment at a set time (default: the day before at 4 PM), only between set hours (default 8 AM–8 PM), and not within a set number of hours of the appointment (default 2). An appointment booked after its reminder time gets one right away. Rescheduling an appointment sends a reminder for the new time.
* **Which**: appointments with the chosen statuses (default: Scheduled), with a customer who has an email address in QuickBooks and hasn't had reminders turned off.
* **What**: a short plain-text and HTML email in your words (placeholders for the customer, vehicle, day, time and shop details), with the appointment attached as a calendar file. A footer says why they got it and to reply if they'd rather not get reminders.
* **Appointment page**: whether the reminder was sent (when, to whom), when it will be, or why it won't be, with **Send now** / **Send again**.
* **Customer page**: turn reminders off (or back on) for a customer.
* **Settings page**: send a test email with the settings as they are on the page, see recent reminders (and why any failed), and send due reminders now.

Each reminder is recorded before it's sent, so a customer never gets two for the same appointment time, even with several Redmine processes. A failed send is tried again (3 times in all); it can always be sent from the appointment page.

## Requirements

* Redmine 7
* redmine_qbo and redmine_qbo_calendar 2026.11.0 or later

## Installation

```
cd /path/to/redmine/plugins
git clone https://github.com/rickbarrette/redmine_qbo_reminders.git
cd ..
bundle exec rake redmine:plugins:migrate
```

Restart Redmine, then set it up under **Administration » Plugins » Redmine QBO Reminders plugin » Configure**, and give roles the permissions they need (administrators always have both):

* **Send appointment reminders**: the **Send now** / **Send again** button on an appointment.
* **Turn appointment reminders off/on for customers**: the **Turn off** / **Turn on** button on a customer.

## Sending through Google Workspace

Reminders go out through Google's mail servers as your mailbox, which keeps them out of spam folders far better than mail sent straight from the Redmine server. Two ways, both included with Google Workspace:

**SMTP relay service (recommended).** In the Google Admin console: Apps » Google Workspace » Gmail » Routing » **SMTP relay service** » Configure:

* Allowed senders: *Only addresses in my domains*
* Authentication: *Require SMTP Authentication* (and/or *Only accept mail from the specified IP addresses* with your server's public IP)
* Encryption: *Require TLS encryption*

Then in the plugin's settings: SMTP server `smtp-relay.gmail.com`, port `587`, domain your domain, and the mailbox's address and an **app password** (or leave both blank when the relay allows your server's IP). The relay allows up to 10,000 messages a day per user.

**Gmail SMTP.** SMTP server `smtp.gmail.com`, port `587`, with the mailbox's address and an app password. Simpler (no Admin console change), with lower daily limits, and each reminder also lands in the mailbox's Sent folder.

App passwords: the mailbox needs 2-Step Verification; then Google Account » Security » **App passwords**. Google no longer accepts the account's regular password over SMTP.

Or choose **Redmine's email settings** to send through whatever `config/configuration.yml` uses. Redmine turns email delivery off when that file has no `email_delivery` section; reminders sent through the plugin's own SMTP server go out regardless, while with Redmine's settings the reminder fails with a message saying delivery is off.

The password is kept in Redmine's plugin settings (in the database), like other plugin settings, and is visible to administrators on the settings page.

## Staying out of spam

1. **DNS.** Make sure your domain has:
   * **SPF**: a TXT record including Google, e.g. `v=spf1 include:_spf.google.com ~all` (one SPF record per domain; add the include to the one you have).
   * **DKIM**: Admin console » Apps » Google Workspace » Gmail » **Authenticate email**: generate a 2048-bit key, publish the TXT record it shows, then click *Start authentication*.
   * **DMARC**: a TXT record at `_dmarc.yourdomain.com`, e.g. `v=DMARC1; p=none; rua=mailto:you@yourdomain.com`. Move to `p=quarantine` once the reports look clean.

   Check by sending a test (settings page) to a Gmail address and choosing **Show original**: SPF, DKIM and DMARC should all say PASS.
2. **From address** on your domain, the same mailbox you send through, with your shop's name as the From name.
3. **Keep the message personal and short.** The default asks customers to reply to confirm; replies help your reputation. Avoid link shorteners and image-only mail.
4. Reminders are transactional, so they don't need an unsubscribe link. The footer still tells customers to reply if they'd rather not get them (so they reply instead of marking the email as spam); when they do, turn reminders off on their customer page. Keep the message free of promotions: that's what keeps it transactional.
5. Optional: [Google Postmaster Tools](https://postmaster.google.com) shows how Gmail sees your domain once you send more.

## Running on schedule

With **Check on page loads** on (the default), Redmine looks for due reminders every 10 minutes while anyone is using it. That's enough when Redmine is open during business hours.

To send them whether or not anyone is using Redmine, run the rake task every 15 minutes from cron:

```
*/15 * * * * cd /path/to/redmine && bundle exec rake redmine:appointment_reminders:send RAILS_ENV=production
```

In Docker Compose, a small service running the same Redmine image can do it, with no cron and no Docker socket. It goes through the image's own start-up script each time, which installs the plugins' gems (as the Redmine container does when it starts), so the task finds everything Redmine uses; that script skips database migrations for rake tasks.

```yaml
  redmine-reminders:
    image: <your redmine image>          # the same image and tag as the Redmine service
    restart: unless-stopped
    depends_on:
      - redmine
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        sleep 120
        while true; do
          /docker-entrypoint.sh rake redmine:appointment_reminders:send || echo "Appointment reminders: run failed"
          sleep 900
        done
    environment:                          # the Redmine service's, without REDMINE_PLUGINS_MIGRATE
      REDMINE_DB_MYSQL: <database host>
      REDMINE_DB_PASSWORD: <database password>
      REDMINE_SECRET_KEY_BASE: ${REDMINE_SECRET_KEY_BASE}
      RAILS_ENV: production
      TZ: America/New_York
      RAILS_LOG_TO_STDOUT: "true"
    volumes:
      - redmine:/usr/src/redmine          # the same volume as the Redmine service
    networks:
      - <the network the database is on>
```

`/docker-entrypoint.sh` is the official Redmine image's start-up script (`docker inspect --format '{{json .Config.Entrypoint}}' <image>` shows yours). The first run takes longer while it installs the gems. Each run prints its result (e.g. `Appointment reminders: 2 sent, 0 failed, 0 skipped`) in that service's log.

(Use the `RAILS_ENV` your Redmine runs in.) The task is safe to run alongside page-load checks.

## Message placeholders

`{{first_name}}` (QuickBooks first name, else the first word of the name), `{{customer}}`, `{{day}}` (Tuesday, November 3), `{{date}}` (11/03/2026), `{{time}}` (9:00 AM), `{{vehicle}}`, `{{subject}}` (the appointment's subject), `{{shop_name}}`, `{{shop_phone}}`, `{{shop_address}}`.

`{{#vehicle}}…{{/vehicle}}` shows its text only when the appointment has a vehicle, and `{{^vehicle}}…{{/vehicle}}` only when it doesn't (any placeholder works). Lines left empty by missing values are dropped.

## Time zone

Appointment times are read as entered, in the **Shop time zone** setting (default Eastern), whatever time zone the server runs in.

## License

MIT
