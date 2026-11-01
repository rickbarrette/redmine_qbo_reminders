#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'cgi'

module RedmineQboReminders
  # The reminder's wording, from the settings. Placeholders:
  #   {{first_name}} {{customer}} {{day}} {{date}} {{time}} {{vehicle}} {{subject}}
  #   {{shop_name}} {{shop_phone}} {{shop_address}}
  # A section shows only when its placeholder has a value ({{#vehicle}}for your {{vehicle}}{{/vehicle}}), and
  # an inverted one only when it doesn't ({{^vehicle}}...{{/vehicle}}).
  module Template
    PLACEHOLDERS = %w[first_name customer day date time vehicle subject shop_name shop_phone shop_address].freeze

    DEFAULT_SUBJECT = 'Reminder: your appointment {{day}} at {{time}}'
    DEFAULT_BODY = <<~TEXT.strip
      Hi {{first_name}},

      This is a reminder of your appointment{{#vehicle}} for your {{vehicle}}{{/vehicle}}{{#shop_name}} at {{shop_name}}{{/shop_name}} on {{day}} at {{time}}.

      Please reply to this email to confirm{{#shop_phone}}, or call us at {{shop_phone}} if you need to reschedule{{/shop_phone}}{{^shop_phone}}, or to let us know if you need to reschedule{{/shop_phone}}.

      Thank you,
      {{shop_name}}
      {{shop_address}}
      {{shop_phone}}
    TEXT

    module_function

    # The text with placeholders filled in (values: { "vehicle" => "2022 Jeep Gladiator", ... })
    def render(text, values)
      values = values.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }
      out = text.to_s.gsub(/\{\{([#^])(\w+)\}\}(.*?)\{\{\/\2\}\}/m) do
        present = values[$2].to_s != ''
        ($1 == '#') == present ? $3 : ''
      end
      out = out.gsub(/\{\{(\w+)\}\}/) { values[$1].to_s }
      # Lines left empty by missing values (e.g. no shop phone) collapse, but paragraph breaks stay
      out.gsub(/[ \t]+$/, '').gsub(/\n{3,}/, "\n\n").strip
    end

    # A one-line version for the subject
    def render_line(text, values)
      render(text, values).gsub(/\s+/, ' ').strip
    end

    # Plain text as simple HTML: paragraphs at blank lines, line breaks kept
    def html(text)
      paragraphs = text.split(/\n{2,}/).map do |para|
        "<p style=\"margin:0 0 1em\">#{para.split("\n").map { |line| CGI.escapeHTML(line) }.join('<br>')}</p>"
      end
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"></head>
        <body style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.5;color:#222">
        #{paragraphs.join("\n")}
        </body></html>
      HTML
    end
  end
end
