# frozen_string_literal: true

require_relative "mutant"

# Fractional dominator credit inside one site (a line, or a subject): the
# killed mutants of a site are grouped by kill set; a kill-set class with no
# proper subset among the site's classes is minimal, and its members share
# one dominator credit (three identical minimal mutants are 1/3 dominator
# each). Every other killed mutant is subsumed (credit 0).
module OperatorYield::Subsumption
  module_function

  def credit(mutants, &site)
    credit = Hash.new(0.0).compare_by_identity
    mutants.select(&:kill_set?).group_by(&site).each_value do |members|
      minimal_classes(members).each do |same|
        same.each { |m| credit[m] = 1.0 / same.size }
      end
    end
    credit
  end

  def minimal_classes(members)
    classes = members.group_by(&:kills)
    classes.select { |set, _| classes.keys.none? { |other| other != set && other.subset?(set) } }.values
  end

  def by_line(mutants) = credit(mutants) { |m| [m.target, m.file, m.line] }
  def by_subject(mutants) = credit(mutants) { |m| [m.target, m.subject] }
end
