require 'minitest/autorun'
require_relative '../phrase_parser'

class PhraseParserTests < Minitest::Test
  def test_simple_query
    tree = PhraseParser.new.parse('foo')
    expected = {
      :query => [
        {:clause => {:term => 'foo'}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_negation_query
    tree = PhraseParser.new.parse('-foo')
    expected = {
      :query => [
        {:clause => {:operator => '-', :term => 'foo'}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_single_word_phrase
    tree = PhraseParser.new.parse('"foo"')
    expected = {
      :query => [
        {:clause => {:phrase => [{:term => 'foo'}]}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_single_phrase
    tree = PhraseParser.new.parse('"foo bar"')
    expected = {
      :query => [
        {:clause => {:phrase => [{:term => 'foo'}, {:term => 'bar'}]}}
      ]
    }
    assert_equal(expected, tree)
  end

  def test_complex_query
    tree = PhraseParser.new.parse('foo -bar +"hello" -"cat in the hat"')
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
end
