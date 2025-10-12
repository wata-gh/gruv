# frozen_string_literal: true

module Redcarpet
  module Render
    class HTML
      def initialize(**); end
    end
  end

  class Markdown
    def initialize(_renderer, **); end

    def render(markdown)
      markdown.to_s.split("\n").map do |line|
        if line.start_with?('# ')
          "<h1>#{line[2..].strip}</h1>"
        elsif line.strip.empty?
          ""
        else
          "<p>#{line.strip}</p>"
        end
      end.join("\n")
    end
  end
end
