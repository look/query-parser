require 'parslet'

module BooleanTermParser
  # This query parser adds an optional operator ("+" or "-") to the simple term
  # parser. In order to do that, a new "clause" node is added to the parse tree.
  class QueryParser < Parslet::Parser
    rule(:term) { match('[a-zA-Z0-9]').repeat(1).as(:term) }
    rule(:operator) { (str('+') | str('-')).as(:operator) }
    rule(:clause) { (operator.maybe >> term).as(:clause) }
    rule(:space)  { match('\s').repeat(1) }
    rule(:query) { (clause >> space.maybe).repeat.as(:query) }
    root(:query)
  end

  class QueryTransformer < Parslet::Transform
    rule(:clause => subtree(:clause)) do
      Clause.new(clause[:operator]&.to_s, clause[:term].to_s)
    end
    rule(:query => sequence(:clauses)) { Query.new(clauses) }
  end

  class Operator
    def self.symbol(str)
      case str
      when '+'
        :must
      when '-'
        :must_not
      when nil
        :should
      else
        raise "Unknown operator: #{str}"
      end
    end
  end

  class Clause
    attr_accessor :operator, :term

    def initialize(operator, term)
      self.operator = Operator.symbol(operator)
      self.term = term
    end
  end

  class Query
    attr_accessor :should_terms, :must_not_terms, :must_terms

    def initialize(clauses)
      self.should_terms = clauses.select { |c| c.operator == :should }.map(&:term)
      self.must_not_terms = clauses.select { |c| c.operator == :must_not }.map(&:term)
      self.must_terms = clauses.select { |c| c.operator == :must }.map(&:term)
    end

    def to_elasticsearch
      query = {
        :query => {
          :bool => {
          }
        }
      }

      if should_terms.any?
        query[:query][:bool][:should] = should_terms.map { |term| match(term) }
      end

      if must_terms.any?
        query[:query][:bool][:must] = must_terms.map { |term| match(term) }
      end

      if must_not_terms.any?
        query[:query][:bool][:must_not] = must_not_terms.map { |term| match(term) }
      end

      query
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
  end
end
