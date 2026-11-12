# frozen_string_literal: true

# Stands in for ActiveRecord's `enum`, keeping the two behaviours of it that
# matter when a model's file is evaluated again: the values are checked before
# anything is defined, and a label whose methods an earlier `enum` defined is
# a conflict, so evaluating a model's class body a second time raises.
module EnumMacro
  CONFLICT = "You tried to define an enum named \"%<enum>s\" on the model \"%<klass>s\", but " \
             "this will generate an instance method \"%<method>s\", which is already defined " \
             "by another enum."

  def enum(name, values)
    raise ArgumentError, "Enum values #{values} must not be empty." if values.empty?
    raise ArgumentError, "Enum values #{values} must not contain a blank name." if values.keys.any? { |key| key.to_s.strip.empty? }

    values.each_key { |label| define_enum_label(name, label.to_s) }
    define_singleton_method(:"#{name}es") { values }
  end

  private

  def define_enum_label(name, label)
    method_name = "#{label}?"
    if enum_methods.method_defined?(method_name)
      raise ArgumentError, format(CONFLICT, enum: name, klass: self.name, method: method_name)
    end

    enum_methods.define_method(method_name) { public_send(name) == label }
  end

  def enum_methods
    @enum_methods ||= Module.new.tap { |mod| include mod }
  end
end
