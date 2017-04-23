# Build a query parser

By [Luke Francl](http://www.recursion.org) ([look@recursion.org](mailto:look@recursion.org)), XXX 2017

More than once in my career, I've been part of a project that needed search. Usually somebody[1] finds the search engine's built-in query parser, wires it up and that is that. It seems like a good idea and saves time upfront. But in the long run, it's better to write your own query parser.

## Problems with generic query parsers

Most search engines have a very powerful query parser built in, which can take a string and convert it to the underlying query objects. I'm most familar with Lucene's query parser which is exposed by [Solr](https://wiki.apache.org/solr/SolrQuerySyntax) and [Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html), but other search APIs provide similar functionality (for example, [Google Cloud Platform's search API](https://cloud.google.com/appengine/docs/standard/python/search/query_strings)).

Exposing this interface directly to users has problems.

### User input may contain special charaters

The built-in query parser has its own syntax, which users may not understand. For example, Elasticsearch's `query_string` syntax reserves `+`, `-`, `=`, `&&`, `||`, `>`, `<`, `!`, `(`, `)`, `{`, `}`, `[`, `]`, `^`, `\"`, `~`, `*`, `?`, `:`, `\`, and `/`

Using the syntax incorrectly will either trigger an error or lead to unexpected results.

    title\:cat "cat:hat"

Escaping characters with regular expressions ranges from difficult to impossible (for example, ensuring balanced quotation marks).

Also, some characters can't be escaped:

> `<` and `>` can’t be escaped at all. The only way to prevent them from attempting to create a range query is to remove them from the query string entirely.

### Intentional or unintential advanced query features

Related to the above point, users can intentionally or unintentionally trigger advanced query features. For example, limiting a search term to a single field with `field_name:term` or boosting a term with `term^10`. The can range from confusing to malicous.

These operators can cause **very** expensive queries. In Lucene-based tools, [certain queries are very expensive](https://lucene.apache.org/core/6_5_0/core/org/apache/lucene/search/AutomatonQuery.html), because they require enumerating terms from the term dctionary in order to generate the query. A query with wildcards (especially a leading wildcard!) or regular expression will do this:

> A query string such as the following would force Elasticsearch to visit every term in the index:
>
> `/.*n/`
>
> Use with caution!

Range queries may seem harmless, but they also have this problem (beware range queries on wide ranges of high resolution data!).

### Huge number of terms

Passing a user input directly to the query parser can be dangerous for more prosaic reasons. For example, the user may simply enter a large number of terms. This will generate a query with many clauses, which will take longer to execute. Truncating the query string is a simple work around, but if you truncate in the middle of an expression (for example, by breaking a quoted phrase or parenthetical expression), it could lead to an invalid query.

## Avoiding the foot gun

Lucene 4.7 added a new `SimpleQueryParser` that improved things quite a bit. In Elasticsearch, this is available as `simple_query_string` in the search DSL. Unlike `query_string`, `simple_quer_string` is designed to be exposed to end users and reduces the complexity of queries that can be created.

But even `SimpleQueryParser` is quite powerful in ways you may not want. [Users can specify](http://lucene.apache.org/core/6_5_0/queryparser/org/apache/lucene/queryparser/simple/SimpleQueryParser.html):

> `+` signifies AND operation<br>
> `|` signifies OR operation<br>
> `-` negates a single token<br>
> `"` wraps a number of tokens to signify a phrase for searching<br>
> `*` at the end of a term signifies a prefix query<br>
> `(` and `)` signify precedence<br>
> `~N` after a word signifies edit distance (fuzziness)<br>
> `~N` after a phrase signifies slop amount

## Taking control of your search box

Often, when you go down the built-in query parser route, you'll get something working quickly, but later run into problems. Users (or your exception monitoring software) complains that queries don't work; or extremely expensive queries slow the service down for everyone.

That's why it's worth the time to build a simple query parser. Here's some advantages:

* Limit queries to the features _you_ need
* Handle expensive queries up front (for example, by limiting the number of terms that can be searched for)
* Better and faster error feedback for users
* perform programmatic modification of search queries before running them (for example, synonym expansion, spelling correction, or removing problematic characters)
* Build in heuristics specific to your application that are not possible for a general-purpose parser (EXAMPLE: date parsing)

In this tutorial, I'll be walking through the creation of a query parser using the Ruby library [Parslet](http://kschiess.github.io/parslet/) that can generate queries for the Elasticsearch query DSL. It will start simple, but build up to supporting terms, boolean operators (`-` and `+`), and phrases. This is a good 80% solution that will work well for most use cases. It's more limited than the syntax supported by `SimpleQueryParser`, but the syntax is controlled by _our_ code now, so we can add new features if _we_ need to.

## Building a term-based query parser

Our first parser will be extremely limited. Given input like "cat in the hat" it can generate this Elasticsearch query:

    {
      "query": {
        "match": {
          "title": {
            "query": "cat in the hat",
            "operator": "or"
          }
        }
      }
    }

This is a [match]() query, which does not interpret its input. You may notice that...we could just take the user input and put it in JSON structure. But we need to start somewhere!

Parslet is a library for generating [Parsing Expression Grammar](https://en.wikipedia.org/wiki/Parsing_expression_grammar)-style parsers. You define the rules of your grammar, and Parslet does the rest.

In the language we are defining, a query is recognized as one or more terms separated by whitespace. A term is defined as one or more characters.

    QUERY
     |    \
     |     \
     TERM   TERM *

In Parslet, this can be expressed as:

XXX: Could work up to this more. This includes capturing with `as`, which is not super obvious.

    {{code="term_parser.rb:3-8"}}

Naming the components with `as` allows us to access them in the parse tree:

    TermParser.new.parse("cat in the hat")
    #=>
    {
      :query => [
        {:term => "cat"@0},
        {:term => "in"@4},
        {:term => "the"@7},
        {:term => "hat"@11}
      ]
    }

The reason why the terms are annotated with a number is that the leaf values of the parse tree are instances of [Parslet::Slice](http://www.rubydoc.info/github/kschiess/parslet/Parslet/Slice) which record where in the string the match began. This is useful for reporting errors.

Once you have defined a grammar for your language, you can create parse trees from strings that conform to that grammar. Then you can define a [Parslet::Transform]() to convert the parse tree into an abstract syntax tree; or in our case, an object that knows how to convert itself to the Elasticsearch query DSL.

A Parlet::Transform defines rules for matching part of the parse tree and converting it to something else. Walking up from the leaf nodes, the entire tree is consumed. For this language, the transformation is simple: match a `:term` Hash and convert it to a String, then match an array of terms and instantiate a `TermQuery` object:

    {{code="term_parser.rb:10-14"}}

`TermQuery` is also simple. It stores its list of term Strings, and defines a `#to_elasticsearch` method that joins them back together again in the query DSL:

    {{code="term_parser.rb:16-35"}}

All together, we can now generate an Elasticsearch `match` query:

    parse_tree = TermParser.new.parse("cat in the hat")
    query = TermTransformer.new.apply(parse_tree)
    query.to_elasticsearch
    # =>
    {
      :query => {
        :match => {
          :title => {
            :query => "cat in the hat",
            :operator => "or"
          }
        }
      }
    }

This is a a roundabout way of generating a simple Elasticsearch query, but now we can build it up.

XXX: OK, that was fun, but so far this could be replaced with a simple match query to Elasticsearch. Let's add boolean operators to the query language.

## Boolean queries: should, must, and must not

Unlike the boolean logic you may be familar with, Lucene-based systems define three types of boolean clauses: **should**, which means that a clause ought to match, but does not reject documents that don't; **must**, which requires documents match the clause; and **must not**, which requires documents do not match the clause. These correspond to "or", "and", and "not", respectively.

In a query language, that might look like this: "cat -hat +cradle". I like using `+` and `-` for this rather than `AND` and `OR` because I think it looks better and users don't have to worry about dangling clauses (for example, "foo AND").

To support boolean logic, we'll add a new entity to our parse tree: a clause. A clause has an optional operator (`+` or `-`) and a term.

```
          Query
            |
            |
         Clause
         /    \
        /      \
     Operator  Term
```

In Parlet, this can be defined like this:

    {{code="boolean_term_parser.rb:5-12"}}

XXX: Show output of parsing a query???

Transforming this parse tree into an Elasticsearch query will be a little more complicated than the previous parser, where we could use `match` directly. Elasticsearch supports several combining queries (XXX: what are these called?) that allow you to combine simpler queries in complicated ways. In this case, we'll use the `bool` query. It looks like this:

```json
{
  "query": {
    "bool": {
      "should": [ list of queries that _should_ match (OR) ],
      "must": [ list of queries that _must_ match (AND)],
      "must_not": [ list of queries that _must not_ match (NOT)]
    }
  }
}
```

As you can see, the input to a bool query is more queries. This is why you can be overwhelmed by `query`, `query`, `query` in a complicated Elasticsearch query.

In order to transform the parse tree into an Elasticsearch boolean query, lets defined a few classes.

First `Operator` is a helper to convert `+`, `-`, or `nil` into `:must`, `:must_not`, or `:should`:

    {{code="operator.rb:1-14"}}

Next, `Clause` holds an `Operator` and a term (which is a `String`):

    {{code="boolean_term_parser.rb:19-26"}}

Then, `BooleanTermQuery` take an Array of clauses and segments them into `should`, `must`, and `must_not` for conversion to an Elasticsearch query hash:

    {{code="boolean_term_parser.rb:28-69"}}

Using these classes, we can write a Parlet transformer to convert the parse tree to a `BooleanTermQuery`:

    {{code="boolean_term_parser.rb:14-17"}}

Since a clause only has a single term, we can use Parslet's `subtree` to consume each `:clause` hash from the tree and convert them to `Clause` instances. Then `sequence` will consume the array of `Clause` objects to create the `BooleanTermQuery`.

    parse_tree = BooleanTermParser.new.parse("cat in the hat")
    query = BooleanTermTransformer.new.apply(parse_tree)
    query.to_elasticsearch
    # => XXX

## Phrase queries

Another important feature for a query parser is to be able to match phrases. In Elasticsearch, this is done with a [match_phrase]() query. The `match_phrase` query can be used as input for the `bool` query, just like the `BooleanTermQuery` used the `match` query. In our query language an example query might look like:

    "cat in the hat" -green +ham

The parse tree looks like this:


```
       Query
         |
       Clause
       /    \
  Operator  Term | Term*
```

    {{code="phrase_term_parser.rb:4-13"}}}

To support phrases, the `Clause` object needs to know whether it is a term clause or a phrase clause. To do this, let's introduce separate classes for `TermClause` and `PhraseClause`:

    {{code="phrase_parser.rb:26-42"}}}

Other than this change, the code stays quite similar to the boolean term query parser. The Phrase query now needs to operate on the clause level rather than the term level, and later when generating the `bool` queries, choose `match` or `match_phrase` depening on the type.

    {{code="phrase_parser.rb:44-112"}}

With these classes defined, the PhraseTransformer can take the parse tree and transform it into a PhraseQuery:

    {{code="phrase_parser.rb:15-24"}}

And here is the Elasticsearch query it generates:

XXX

With these features, this is a respectable query parser. It supports a simple syntax that's easy to understand and hard to mess up, and more importantly, hard to abuse. From here, we could improve the query parser in many ways to make it more robust. For example, we could limit phrases to 4 terms or limit the total number of clauses to 10. Because we are parsing the query oursleves, we can make decisions about what gets sent to Elasticsearch in an intelligent way that won't cause broken queries.

## Going beyond generic query parsers: Adding heuristics

So far, what we've built has been aimed at preventing harmful queries -- and providing a simple query user experience. However, another benefit of building your own query parser is that since it is specific to your application, you can tailor it to your domain.

For example, let's say we are building search for a database of books. We know a lot about the data, and can develop heuristics for users search input. Let's say that we know all publication dates for books in the catalog are in the range 1950 - present. Therefore, queries like "50s" are unabiguous. We can expand these queries to do a date range query for books published between 1950-1960. Since we control the parser, we can also search for the text the user entered literally.

An example search might look like this:

    cats 1970s

The query we want to generate is:

```json
{
  "query": {
    "bool": {
      "should": [
        "match": {
          "title": "cats"
        },
        "range": {
          XXX
        }
      ]
    }
  }
}
```


## Error handling

???

## Source code

XXX: Something about where to find the source code, how it's organized?

## Appendix 1: Using Parslet from the console

```ruby
require 'parslet'
include Parslet

match('\d').repeat(1).parse("1234")
 => "1234"@0
 ```

## Resources

The parslet tutorial is an excellent resource.

Talk about Parslet:
https://www.youtube.com/watch?v=ET_POMJNWNs

https://jeffreykegler.github.io/Ocean-of-Awareness-blog/individual/2015/03/peg.html
https://www.codeproject.com/Articles/10115/Crafting-an-interpreter-Part-Parsing-and-Grammar


[1] OK, it was me.

[1] see the accompanying repository for the sample data

[2] match query is actually sufficient to do this by itself. xxxxxx
