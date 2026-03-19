# frozen_string_literal: true

namespace :memory do
  desc "Run memory leak checks against fixture workload"
  task :check do
    script = File.expand_path("../../script/memory_check", __dir__)
    system("ruby", script) || abort("Memory check failed!")
  end
end
