require 'minitest/autorun'
require_relative '../boolean_term_parser'

class BooleanTermTransformerTests < Minitest::Test
  def test_boolean_term_transformer
    parsed_query = {
      :query => [
        {
          :clause => {
            :operator => '-',
            :term => 'cat'
          }
        },
        {
          :clause => {
            :term => 'hat'
          }
        }
      ]
    }

    boolean_term_query = BooleanTermParser::QueryTransformer.new.apply(parsed_query)

    assert_equal(0, boolean_term_query.must_terms.size)
    assert_equal(['hat'], boolean_term_query.should_terms)
    assert_equal(['cat'], boolean_term_query.must_not_terms)
  end
end
