# frozen_string_literal: true

require_relative "lib/evilution/version"

Gem::Specification.new do |spec|
  spec.name = "evilution"
  spec.version = Evilution::VERSION
  spec.authors = ["Denis Kiselev"]
  spec.email = ["denis.kiselyov@gmail.com"]
  spec.license = "MIT"
  spec.summary = "Free, MIT-licensed mutation testing for Ruby"
  spec.homepage = "https://github.com/marinazzio/evilution"

  spec.required_ruby_version = ">= 3.3.0"

  spec.description = "Evilution is a mutation testing tool for Ruby. " \
                     "It validates test suite quality by making small code changes and " \
                     "checking if tests catch them. AI-agent-first design with JSON output, " \
                     "diff-based targeting, and coverage-based filtering."

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "bug_tracker_uri" => "https://github.com/marinazzio/evilution/issues",
    "documentation_uri" => "https://github.com/marinazzio/evilution/blob/master/README.md",

    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true",
    "source_code_uri" => spec.homepage
  }

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "diff-lcs", ">= 1.5", "< 3"
end
