require 'minitest/autorun'
require_relative '../term_parser'

class TermTransformerTests < Minitest::Test
  def test_single_term
    parsed_query = {:query => [{:term => 'foo'}]}
    term_query = TermTransformer.new.apply(parsed_query)
    assert_equal(['foo'], term_query.terms)
  end

  def test_multiple_terms
    parsed_query = {:query => [{:term => 'foo'}, {:term => 'bar'}, {:term => 'baz'}]}
    term_query = TermTransformer.new.apply(parsed_query)
    assert_equal(['foo', 'bar', 'baz'], term_query.terms)
  end
end
