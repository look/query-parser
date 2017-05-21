require 'minitest/autorun'
require_relative '../heuristic_parser'

class HeuristicParserTest < Minitest::Test
  def test_date_range
    tree = HeuristicParser::QueryParser.new.parse("1990s 2010")
    assert_equal({:query => [{:clause => {:decade => '1990'}}, {:clause => {:decade => '2010'}}]}, tree)
  end

  def test_complex_query
    tree = HeuristicParser::QueryParser.new.parse('awesome "cat videos" -2000s')
    expected = {:query => [{:clause => {:term => 'awesome'}},
                           {:clause => {:phrase => [{:term => 'cat'}, {:term => 'videos'}]}},
                           {:clause => {:operator => '-', :decade => '2000'}}]}

    assert_equal(expected, tree)
  end
end
