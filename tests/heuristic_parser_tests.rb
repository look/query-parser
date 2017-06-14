require 'minitest/autorun'
require_relative '../heuristic_parser'

class HeuristicParserTest < Minitest::Test
  def test_date_range
    tree = HeuristicParser::QueryParser.new.parse("1990s 2010")
    assert_equal({:query => [{:clause => {:decade => '1990'}}, {:clause => {:decade => '2010'}}]}, tree)
  end

  def test_complex_query
    tree = HeuristicParser::QueryParser.new.parse('+paw-some "cat videos" -2000s')
    expected = {:query => [{:clause => {:operator => '+', :term => 'paw-some'}},
                           {:clause => {:phrase => [{:term => 'cat'}, {:term => 'videos'}]}},
                           {:clause => {:operator => '-', :decade => '2000'}}]}

    assert_equal(expected, tree)
  end

  def test_term_prefixed_with_decade
    tree = HeuristicParser::QueryParser.new.parse('2000st')
    expected = {:query => [{:clause => {:term => '2000st'}}]}
    assert_equal(expected, tree)
  end

  def test_term_suffixed_with_decade
    tree = HeuristicParser::QueryParser.new.parse('st2000')
    expected = {:query => [{:clause => {:term => 'st2000'}}]}
    assert_equal(expected, tree)
  end

  def test_non_decade_parsed_as_term
    tree = HeuristicParser::QueryParser.new.parse('2001')
    expected = {:query => [{:clause => {:term => '2001'}}]}
    assert_equal(expected, tree)
  end
end
