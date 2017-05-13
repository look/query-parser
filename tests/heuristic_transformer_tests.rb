require 'minitest/autorun'
require_relative '../heuristic_parser'

class HeuristicTransformerTest < Minitest::Test
  def test_heuristic_transformer
    parsed_query = {
      :query => [
        {:clause => {:term => 'awesome'}},
        {:clause => {:phrase => [{:term => 'cat'}, {:term => 'videos'}]}},
        {:clause => {:operator => '-', :decade => '2000'}}
      ]
    }

    query = HeuristicTransformer.new.apply(parsed_query)
    assert(query.should_clauses.size, 2)
    assert(query.must_clauses.size, 0)
    assert(query.must_not_clauses.size, 1)
    assert_equal('awesome', query.should_clauses.first.term)
    assert_equal('cat videos', query.should_clauses[1].phrase)
    assert_equal(2000, query.must_not_clauses.first.start_year)
    assert_equal(2009, query.must_not_clauses.first.end_year)
  end
end
