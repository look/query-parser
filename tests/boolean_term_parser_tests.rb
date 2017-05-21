require 'minitest/autorun'
require_relative '../boolean_term_parser'

class BooleanTermParserTests < Minitest::Test
  def test_single_term
    tree = BooleanTermParser::QueryParser.new.parse('foo')
    assert_equal({:query => [{:clause => {:term => 'foo'}}]}, tree)
  end

  def test_single_term_with_operator
    tree = BooleanTermParser::QueryParser.new.parse('-foo')
    assert_equal({:query => [{:clause => {:operator => '-', :term => 'foo'}}]}, tree)
  end

  def test_multiple_terms
    tree = BooleanTermParser::QueryParser.new.parse('foo bar baz')
    expected = {:query => [{:clause => {:term => 'foo'}},
                           {:clause => {:term => 'bar'}},
                           {:clause => {:term => 'baz'}}]}
    assert_equal(expected, tree)
  end

  def test_multiple_terms_with_operators
    tree = BooleanTermParser::QueryParser.new.parse("foo +bar +baz -cat")
    expected = {:query => [{:clause => {:term => 'foo'}},
                           {:clause => {:operator => '+', :term => 'bar'}},
                           {:clause => {:operator => '+', :term => 'baz'}},
                           {:clause => {:operator => '-', :term => 'cat'}}]}
    assert_equal(expected, tree)
  end
end
