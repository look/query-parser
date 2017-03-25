require_relative 'term_parser'
require_relative 'boolean_term_parser'
require 'minitest/autorun'
require 'awesome_print'

class ParserTests < Minitest::Test
  def test_term_parser
    tree = TermParser.new.parse("foo bar baz")
    ap tree

    term_query = TermTransformer.new.apply(tree)
    ap term_query.to_elasticsearch
  end

  def test_boolean_parser
    tree = BooleanTermParser.new.parse("foo +bar +baz -cat")
    ap tree

    query = BooleanTermTransformer.new.apply(tree)
    ap query
    ap query.to_elasticsearch
  end
end
