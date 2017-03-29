require_relative 'term_parser'
require_relative 'boolean_term_parser'
require_relative 'phrase_parser'
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

  def test_phrase_parser
    tree = PhraseParser.new.parse('+foo -"cat in the hat"')
    ap tree

    query = PhraseTransformer.new.apply(tree)
    ap query
    ap query.to_elasticsearch
  end

  def test_phrase_transformer
    parsed_query = {:query=>[{:clause=>{:operator=>"+", :term=>"foo"}},
                             {:clause => {:term => "bar"}},
                             {:clause=>{:operator=>"-", :phrase=>[{:term=>"cat"}, {:term=>"in"}, {:term=>"the"}, {:term=>"hat"}]}}]}

    phrase_query = PhraseTransformer.new.apply(parsed_query)
    ap phrase_query

    assert_empty phrase_query.should_clauses
    assert(phrase_query.must_clauses.size, 1)
    assert(phrase_query.must_not_clauses.size, 1)
    assert_equal("foo", phrase_query.must_clauses.first.term)
    assert_equal("bar", phrase_query.should_clauses.first.term)
    assert_equal("cat in the hat", phrase_query.must_not_clauses.first.phrase)
  end
end
