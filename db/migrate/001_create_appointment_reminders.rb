#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# One row per reminder sent (or tried) for an appointment at a given time; rescheduling the appointment
# makes it due again
class CreateAppointmentReminders < ActiveRecord::Migration[7.0]
  def change
    create_table :appointment_reminders do |t|
      t.references :customer_appointment, null: false
      t.datetime :appointment_date, null: false
      t.string :email
      # pending (being sent), sent or failed
      t.string :status, null: false, default: 'pending'
      t.text :error
      t.integer :attempts, null: false, default: 0
      t.datetime :sent_at
      # Who sent it from the appointment page; empty when sent on schedule
      t.references :sent_by
      t.timestamps
    end
    add_index :appointment_reminders, [:customer_appointment_id, :appointment_date], unique: true,
              name: 'index_appointment_reminders_on_appointment_and_date'
    add_index :appointment_reminders, :created_at
  end
end
