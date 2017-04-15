require 'parslet'

class TermParser < Parslet::Parser
  rule(:term) { match('[a-zA-Z0-9]').repeat(1).as(:term) }
  rule(:space)  { match('\s').repeat(1) }
  rule(:query) { (term >> space.maybe).repeat.as(:query) }
  root(:query)
end

class TermTransformer < Parslet::Transform
  rule(:term => simple(:term)) { term.to_s }
  rule(:query => sequence(:terms)) { TermQuery.new(terms) }
end

# A query represented by a list of parsed user terms
class TermQuery
  attr_accessor :terms

  def initialize(terms)
    self.terms = terms
  end

  def to_elasticsearch
    {
      :query => {
        :match => {
          :title => {
            :query => terms.join(" "),
            :operator => "or"
          }
        }
      }
    }
  end
end
