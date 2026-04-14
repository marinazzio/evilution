# frozen_string_literal: true

require "erb"
require_relative "namespace"
require_relative "escape"

class Evilution::Reporter::HTML::Section
  TEMPLATE_DIR = File.expand_path("templates", __dir__)

  def self.template(name)
    path = File.join(TEMPLATE_DIR, "#{name}.html.erb")
    erb = ERB.new(File.read(path), trim_mode: "-")
    erb.def_method(self, "render")
  end

  private

  def h(text)
    Evilution::Reporter::HTML::Escape.call(text)
  end
end
