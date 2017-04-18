require 'minitest/autorun'
require_relative '../../phrase_parser'
require_relative '../../elasticsearch_helpers'

class SearchTest < Minitest::Test

  def self.configure_es
    return if defined?(@configured)

    ElasticsearchHelpers.prepare_corpus!

    @configured = true
  end

  def setup
    self.class.configure_es
  end

  def test_query
    query_dsl = PhraseQuery.elasticsearch_query_for('kill "cat is plotting"')
    results = ElasticsearchHelpers.search(query_dsl)

    hits = results['hits']['hits']
    assert_equal(1, hits.size)
    assert_equal('How to Tell If Your Cat Is Plotting to Kill You', hits.first['_source']['title'])
  end

  def test_negation_query
    query_dsl = PhraseQuery.elasticsearch_query_for('cat -hat')
    results = ElasticsearchHelpers.search(query_dsl)

    hits = results['hits']['hits']
    assert_equal(2, hits.size)
    titles = hits.map { |h| h['_source']['title'] }
    refute_includes(titles, "The Cat in the Hat")
  end
end
