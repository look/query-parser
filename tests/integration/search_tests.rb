require 'minitest/autorun'
require_relative '../../heuristic_parser'
require_relative '../../elasticsearch_helpers'

class SearchTests < Minitest::Test

  def self.configure_es
    return if defined?(@configured)

    ElasticsearchHelpers.prepare_corpus!

    @configured = true
  end

  def setup
    self.class.configure_es
  end

  def test_query
    query_dsl = HeuristicParser::Query.elasticsearch_query_for('kill "cat is plotting"')
    results = ElasticsearchHelpers.search(query_dsl)

    hits = results.fetch('hits').fetch('hits')
    assert_equal(1, hits.size)
    assert_equal('How to Tell If Your Cat Is Plotting to Kill You', hits.first.fetch('_source').fetch('title'))
  end

  def test_negation_query
    query_dsl = HeuristicParser::Query.elasticsearch_query_for('cat -hat')
    results = ElasticsearchHelpers.search(query_dsl)

    hits = results.fetch('hits').fetch('hits')
    assert_equal(2, hits.size)
    titles = hits.map { |h| h.fetch('_source').fetch('title') }
    refute_includes(titles, 'The Cat in the Hat')
  end

  def test_date_range_query
    query_dsl = HeuristicParser::Query.elasticsearch_query_for('1950s')
    results = ElasticsearchHelpers.search(query_dsl)

    hits = results.fetch('hits').fetch('hits')
    assert_equal(1, hits.size)
    assert_equal('The Cat in the Hat', hits.first.fetch('_source').fetch('title'))
  end

  def test_negation_date_range_query
    query_dsl = HeuristicParser::Query.elasticsearch_query_for('-2010')
    results = ElasticsearchHelpers.search(query_dsl)

    hits = results.fetch('hits').fetch('hits')
    assert_equal(1, hits.size)
    assert_equal('The Cat in the Hat', hits.first.fetch('_source').fetch('title'))
  end
end
