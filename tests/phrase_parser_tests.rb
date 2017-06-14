require 'minitest/autorun'
require_relative '../phrase_parser'

class PhraseParserTests < Minitest::Test
  def test_simple_query
    tree = PhraseParser::QueryParser.new.parse('foo')
    expected = {
      :query => [
        {:clause => {:term => 'foo'}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_negation_query
    tree = PhraseParser::QueryParser.new.parse('-foo')
    expected = {
      :query => [
        {:clause => {:operator => '-', :term => 'foo'}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_single_word_phrase
    tree = PhraseParser::QueryParser.new.parse('"foo"')
    expected = {
      :query => [
        {:clause => {:phrase => [{:term => 'foo'}]}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_single_phrase
    tree = PhraseParser::QueryParser.new.parse('"foo bar"')
    expected = {
      :query => [
        {:clause => {:phrase => [{:term => 'foo'}, {:term => 'bar'}]}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_complex_query
    tree = PhraseParser::QueryParser.new.parse('foo -bar +"hello" -"cat in the hat"')
    expected = {
      :query => [
        {
          :clause => {:term => 'foo'}
        },
        {
          :clause => {:operator => '-', :term => 'bar'}
        },
        {
          :clause => {
            :operator => '+',
            :phrase => [{:term => 'hello'}]
          }
        },
        {
          :clause => {
            :operator => '-',
            :phrase => [{:term => 'cat'}, {:term => 'in'}, {:term => 'the'}, {:term => 'hat'}]
          }
        }
      ]
    }

    assert_equal(expected, tree)
  end

  def test_mismatched_quotation_marks
    assert_raises Parslet::ParseFailed do
      PhraseParser::QueryParser.new.parse('"foo')
    end
  end

  def test_quotation_mark_in_term
    assert_raises Parslet::ParseFailed do
      PhraseParser::QueryParser.new.parse('fo"o')
    end
  end

  def test_mismatched_quotation_mark_delimiter
    # We'll call this a "feature" since the quotation marks are balanced.
    # If you don't want this, you can use lookahead to ensure end-quote is followed by a space or EOF
    tree = PhraseParser::QueryParser.new.parse('"foo"+bar"baz"')
    expected = {:query => [{:clause => {:phrase => [{:term => 'foo'}]}},
                           {:clause => {:operator => '+', :term => 'bar'}},
                           {:clause => {:phrase => [{:term => 'baz'}]}}]}
    assert_equal(expected, tree)
  end
end
