# frozen_string_literal: true

module CLIHelpers
  def capture_stdout
    io = StringIO.new
    original = $stdout
    $stdout = io
    yield
    io.string
  ensure
    $stdout = original
  end

  def capture_stderr
    io = StringIO.new
    original = $stderr
    $stderr = io
    yield
    io.string
  ensure
    $stderr = original
  end
end
