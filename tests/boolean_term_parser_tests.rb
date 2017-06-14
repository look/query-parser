# coding: utf-8
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

  def test_non_ascii_characters
    tree = BooleanTermParser::QueryParser.new.parse('+føé -ba∑ ∫åñ')
    expected = {:query => [{:clause => {:operator => '+', :term => 'føé'}},
                           {:clause => {:operator => '-', :term => 'ba∑'}},
                           {:clause => {:term => '∫åñ'}}]}
    assert_equal(expected, tree)
  end

  def test_operators_in_terms
    tree = BooleanTermParser::QueryParser.new.parse('-foo+term +bar-term baz-term')
    expected = {:query => [{:clause => {:operator => '-', :term => 'foo+term'}},
                           {:clause => {:operator => '+', :term => 'bar-term'}},
                           {:clause => {:term => 'baz-term'}}]}
    assert_equal(expected, tree)
  end

  def test_quotation_marks
    tree = BooleanTermParser::QueryParser.new.parse('+fo"o -ba"r')
    expected = {:query => [{:clause => {:operator => '+', :term => 'fo"o'}},
                           {:clause => {:operator => '-', :term => 'ba"r'}}]}
    assert_equal(expected, tree)
  end
end
