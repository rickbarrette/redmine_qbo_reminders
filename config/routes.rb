#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

RedmineApp::Application.routes.draw do
  post 'customer_appointments/:id/reminder', to: 'appointment_reminders#send_now', as: 'send_appointment_reminder'
  post 'customers/:customer_id/reminders/off', to: 'appointment_reminders#opt_out', as: 'customer_reminders_off'
  post 'customers/:customer_id/reminders/on', to: 'appointment_reminders#opt_in', as: 'customer_reminders_on'
  # From the plugin's settings page (administrators)
  post 'appointment_reminders/test', to: 'appointment_reminders#test', as: 'test_appointment_reminder'
  post 'appointment_reminders/run', to: 'appointment_reminders#run', as: 'run_appointment_reminders'
end
