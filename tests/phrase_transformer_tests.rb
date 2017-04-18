require 'minitest/autorun'
require_relative '../phrase_parser'

class PhraseTransformerTests < Minitest::Test
  def test_phrase_transformer
    parsed_query = {
      :query => [
        {
          :clause => {
            :operator => "+", :term => "foo"
          }
        },
        {
          :clause => {
            :term => "bar"
          }
        },
        {
          :clause => {
            :operator => "-",
            :phrase => [
              {:term => "cat"},
              {:term => "in"},
              {:term => "the"},
              {:term => "hat"}
            ]
          }
        }
      ]
    }

    phrase_query = PhraseTransformer.new.apply(parsed_query)

    assert(phrase_query.should_clauses.size, 1)
    assert(phrase_query.must_clauses.size, 1)
    assert(phrase_query.must_not_clauses.size, 1)
    assert_equal("foo", phrase_query.must_clauses.first.term)
    assert_equal("bar", phrase_query.should_clauses.first.term)
    assert_equal("cat in the hat", phrase_query.must_not_clauses.first.phrase)
  end

  def test_single_word_phrase
    parsed_query = {
      :query  => [
        {
          :clause => {
            :phrase => [{:term => "bar"}]
          }
        }
      ]
    }

    phrase_query = PhraseTransformer.new.apply(parsed_query)
    assert(phrase_query.should_clauses.size, 1)
    assert("bar", phrase_query.should_clauses.first.phrase)
  end
end
