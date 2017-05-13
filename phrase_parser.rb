require 'parslet'
require_relative 'operator'

class PhraseParser < Parslet::Parser
  rule(:term) { match('[a-zA-Z0-9]').repeat(1).as(:term) }
  rule(:quote) { str('"') }
  rule(:operator) { (str('+') | str('-')).as(:operator) }
  rule(:phrase) { (quote >> (term >> space.maybe).repeat >> quote).as(:phrase) }
  rule(:clause) { (operator.maybe >> (phrase | term)).as(:clause) }
  rule(:space)  { match('\s').repeat(1) }
  rule(:query) { (clause >> space.maybe).repeat.as(:query) }
  root(:query)
end

class PhraseTransformer < Parslet::Transform
  rule(:clause => subtree(:clause)) do
    if clause[:term]
      TermClause.new(clause[:operator]&.to_s, clause[:term].to_s)
    elsif clause[:phrase]
      PhraseClause.new(clause[:operator]&.to_s, clause[:phrase].map { |p| p[:term].to_s }.join(" "))
    else
      raise "Unexpected clause type: '#{clause}'"
    end
  end
  rule(:query => sequence(:clauses)) { PhraseQuery.new(clauses) }
end

class TermClause
  attr_accessor :operator, :term

  def initialize(operator, term)
    self.operator = Operator.symbol(operator)
    self.term = term
  end
end

class PhraseClause
  attr_accessor :operator, :phrase

  def initialize(operator, phrase)
    self.operator = Operator.symbol(operator)
    self.phrase = phrase
  end
end

class PhraseQuery
  attr_accessor :should_clauses, :must_not_clauses, :must_clauses

  def self.elasticsearch_query_for(query_string)
    tree = PhraseParser.new.parse(query_string)
    query = PhraseTransformer.new.apply(tree)
    query.to_elasticsearch
  end

  def initialize(clauses)
    self.should_clauses = clauses.select { |c| c.operator == :should }
    self.must_not_clauses = clauses.select { |c| c.operator == :must_not }
    self.must_clauses = clauses.select { |c| c.operator == :must }
  end

  def to_elasticsearch
    query = {
      :query => {
        :bool => {
        }
      }
    }

    if should_clauses.any?
      query[:query][:bool][:should] = should_clauses.map { |clause| clause_to_query(clause) }
    end

    if must_clauses.any?
      query[:query][:bool][:must] = must_clauses.map { |clause| clause_to_query(clause) }
    end

    if must_not_clauses.any?
      query[:query][:bool][:must_not] = must_not_clauses.map { |clause| clause_to_query(clause) }
    end

    query
  end

  def clause_to_query(clause)
    case clause
    when TermClause
      match(clause.term)
    when PhraseClause
      match_phrase(clause.phrase)
    else
      raise "Unknown clause type: #{clause}"
    end
  end

  def match(term)
    {
      :match => {
        :title => {
          :query => term
        }
      }
    }
  end

  def match_phrase(phrase)
    {
      :match_phrase => {
        :title => {
          :query => phrase
        }
      }
    }
  end
end
