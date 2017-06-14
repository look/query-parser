# coding: utf-8
require 'minitest/autorun'
require_relative '../term_parser'

class TermParserTests < Minitest::Test
  def test_single_term
    tree = TermParser::QueryParser.new.parse('foo')
    assert_equal({:query => [{:term => 'foo'}]}, tree)
  end

  def test_multiple_terms
    tree = TermParser::QueryParser.new.parse('foo bar baz')
    assert_equal({:query => [{:term => 'foo'}, {:term => 'bar'}, {:term => 'baz'}]}, tree)
  end

  def test_multiple_spaces_between_terms
    tree = TermParser::QueryParser.new.parse('foo    bar')
    assert_equal({:query => [{:term => 'foo'}, {:term => 'bar'}]}, tree)
  end

  def test_non_ascii_characters
    tree = TermParser::QueryParser.new.parse('føé ba∑')
    assert_equal({:query => [{:term => 'føé'}, {:term => 'ba∑'}]}, tree)
  end

  def test_quotation_marks
    tree = TermParser::QueryParser.new.parse('fo"o')
    assert_equal({:query => [{:term => 'fo"o'}]}, tree)
  end
end
