<h1 class="title">Build a query parser</h1>
<h2 class="subtitle">Why and how, with an example using Ruby, Parslet, and Elasticsearch</h2>

_By [Luke Francl](http://www.recursion.org) ([look@recursion.org](mailto:look@recursion.org)), XXX 2017_

More than a few times in my career, I've been part of a project that needed search. A Lucene-based search engine fits the bill. Somebody<sup id="fn1-body">[1](#fn1)</sup> finds the search engine's built-in query parser, wires it up, and that is that. It seems like a good idea and it's easy.

However, it's better to write your own query parser, for two reasons. First, **built-in parsers are too powerful**. They are confusing and allow users to trigger expensive queries that kill performance. Second, **built-in parsers are too generic**. There is a tension between queries that are safe to execute and giving users a powerful query language&mdash;which they expect. However, built-in query parsers tend to be all-or-nothing: either they are safe, or they provide extraordinary power that can be too dangerous to expose. You can't select only the features you need. When you control your own parser, you can add features to it and customize _your_ application's search behavior for _your_ users.

This might sound daunting, but thanks to easy-to-use parser libraries, it's straightforward. There is **no magic** in the built-in query parser. It constructs low-level queries the same way as using those objects directly.

In this tutorial, we'll create a query parser that can generate queries for the [Elasticsearch query DSL](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl.html). Building up from a simple term parser, we'll add boolean operators, phrases, and close by adding an application-specific heuristic that would never make sense as part of a generic query parser.

Want to skip to the code? Each step of the tutorial [is available as a self-contained file](https://github.com/look/query-parser) so it's easy to follow along.

<div class="toc">

## Table of contents

* [Problems with generic query parsers](#problems_with_generic_query_parsers)
  * [There is no magic: The power-safety gradient](#there_is_no_magic_the_safetypower_gradient)
  * [User input may contain special characters](#user_input_may_contain_special_characters)
  * [Users can trigger expensive query features](#users_can_trigger_expensive_query_features)
  * [Users can submit a huge number of terms](#users_can_submit_a_huge_number_of_terms)
  * [Avoiding the foot gun](#avoiding_the_foot_gun)
* [Take control of your search box](#take_control_of_your_search_box)
* [Building a term-based query parser](#building_a_termbased_query_parser)
  * [Defining a query language grammar with BNF](#defining_a_query_language_grammar_with_bnf)
  * [Defining a grammar with Parslet](#defining_a_grammar_with_parslet)
  * [Building a parse tree](#building_a_parse_tree)
* [Boolean queries: should, must, and must not](#boolean_queries_should_must_and_must_not)
* [Phrase queries](#phrase_queries)
* [Going beyond generic query parsers: Adding heuristics](#going_beyond_generic_query_parsers_adding_heuristics)
* [Next steps](#next_steps)
  * [Improving search relevance](#improving_search_relevance)
  * [Error handling, reporting, and fallback](#error_handling_reporting_and_fallback)
  * [Limiting query complexity](#limiting_query_complexity)
  * [Field configuration for query generation](#field_configuration_for_query_generation)
* [Further reading](#further_reading)

</div>

## Problems with generic query parsers

Most search engines have a very powerful query parser built in, which can take a string and convert it to the underlying query objects. I'm most familiar with Lucene's query parser which is exposed by [Solr](https://wiki.apache.org/solr/SolrQuerySyntax) and [Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html), but other search APIs provide similar functionality (for example, [Google Cloud Platform's search API](https://cloud.google.com/appengine/docs/standard/python/search/query_strings)).

### There is no magic: The safety-power gradient

There is no magic in the Lucene query parser. It accepts as input a string, parses it and constructs lower-level queries. You can see this yourself if you [look at the code](https://github.com/apache/lucene-solr/blob/master/lucene/queryparser/src/java/org/apache/lucene/queryparser/flexible/standard/builders/AnyQueryNodeBuilder.java) (the linked-to class adds `should` clauses to a boolean query.)

The following Elasticsearch query looks simple:

```json
{
  "query": {
    "simple_query_string" : {
        "query": "cat in the hat",
        "fields": ["title"]
    }
  }
}
```

But it is essentially the same as this longer query that has been implemented using [`bool`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html) and [`match`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-match-query.html):

```json
{
  "query": {
    "bool": {
      "should": [
        {
          "match": {
            "title": {
              "query": "cat"
            }
          }
        },
        {
          "match": {
            "title": {
              "query": "in"
            }
          }
        },
        {
          "match": {
            "title": {
              "query": "the"
            }
          }
        },
        {
          "match": {
            "title": {
              "query": "hat"
            }
          }
        }
      ]
    }
  }
}
```

And `match` is implemented using [`term`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-term-query.html), which is a query that [operates on the exact terms that are stored in Lucene's inverted index](https://www.elastic.co/guide/en/elasticsearch/reference/current/term-level-queries.html).

The higher-level queries are all implemented in terms of the lower-level queries.

    {{svg="safety-vs-power.svg"}}

* `term`: Exact match for a single term
* `match`: Constructs a `bool` query of analyzed terms (no parsing)
* `simple_query_string`: Parses a string and constructs a `bool` query with phrases, fuzziness, and prefixes
* `query_string`: Parses a very complicated syntax and constructs a `bool` query with phrases, fuzziness, prefixes, ranges, regular expressions, etc.
    
`match` is very safe to expose to users, but also limited in what it can do. The jump up to `simple_query_parser` adds a lot of features you may not need, and `query_string` is explicitly not recommended.
    
However, since there is no magic, there is no downside to generating lower-level queries in your application, rather than having Elasticsearch do it.

### User input may contain special characters

The built-in query parser has its own syntax, which users may not understand. For example, [Elasticsearch's `query_string` syntax reserves](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html#_reserved_characters) `+`, `-`, `=`, `&&`, `||`, `>`, `<`, `!`, `(`, `)`, `{`, `}`, `[`, `]`, `^`, `"`, `~`, `*`, `?`, `:`, `\`, and `/`.

Using the syntax incorrectly will either trigger an error or lead to unexpected results. For example, to prevent the query string <span class="query-string">alpha:cat "cat:hat"</span> from generating a query limiting the search for <span class="query-string">cat</span> to the field `alpha` (which might not exist), it should be escaped as <span class="query-string">alpha\:cat "cat:hat"</span>.

Escaping characters in a query string with regular expressions ranges from difficult to impossible. And some characters [can't be escaped, period](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html#_reserved_characters):

> `<` and `>` can't be escaped at all. The only way to prevent them from attempting to create a range query is to remove them from the query string entirely.

Exposing `query_string` to end users is now explicitly discouraged. Considering its complexity and lack of composability, it's not a great interface for programmers, either.

### Users can trigger expensive query features

Related to the above point, users can intentionally or unintentionally trigger advanced query features. For example, limiting a search term to a single field with <span class="query-string">field_name:term</span> or boosting a term with <span class="query-string">term^10</span>. The results can range from confusing to malicious.

Some of these advanced operators can cause **very** expensive queries. In Lucene-based tools, [certain queries are very expensive](https://lucene.apache.org/core/6_5_0/core/org/apache/lucene/search/AutomatonQuery.html) because they require enumerating terms from the term dictionary in order to create the low-level query objects. A [query with a wildcard](https://www.quora.com/What-is-the-algorithm-used-by-Lucenes-PrefixQuery) (especially a leading wildcard!) or regular expression may require reading **many** terms. Regular expressions are [particularly dangerous](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html#_regular_expressions):

> A query string such as the following would force Elasticsearch to visit every term in the index:
>
> `/.*n/`
>
> Use with caution!

Range queries may seem harmless, but they [also have this problem](http://george-stathis.com/2013/10/18/setting-the-booleanquery-maxclausecount-in-elasticsearch/). Beware queries for wide ranges on high resolution data!

### Users can submit a huge number of terms

Passing a user input directly to the query parser can be dangerous for more prosaic reasons. For example, the user may simply enter a large number of terms. This will generate a query with many clauses, which will take longer to execute. Truncating the query string is a simple work around, but if you truncate in the middle of an expression (for example, by breaking a quoted phrase or parenthetical expression), it could lead to an invalid query.

### Avoiding the foot gun

Lucene 4.7 added a new `SimpleQueryParser` that improved things quite a bit. In Elasticsearch, [this is available as `simple_query_string`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-simple-query-string-query.html) in the search DSL. Unlike `query_string`, `simple_query_string` is designed to be exposed to end users and reduces the complexity of queries that can be created.

But `SimpleQueryParser` is still powerful. [Users can specify](http://lucene.apache.org/core/6_5_0/queryparser/org/apache/lucene/queryparser/simple/SimpleQueryParser.html) queries with the following operators:

> `+` signifies AND operation<br>
> `|` signifies OR operation<br>
> `-` negates a single token<br>
> `"` wraps a number of tokens to signify a phrase for searching<br>
> `*` at the end of a term signifies a prefix query<br>
> `(` and `)` signify precedence<br>
> `~N` after a word signifies edit distance (fuzziness)<br>
> `~N` after a phrase signifies slop amount

This syntax is both complicated and may let users generate expensive queries.

## Take control of your search box

Often, when you go down the built-in query parser route, you'll get something working quickly, but later run into problems. Users (or your exception monitoring software) complain that queries don't work; or extremely expensive queries slow the service down for everyone.

<div class="aside">

### Aside: Search box versus search interface

This tutorial focuses on parsing what the user types into a search box: full-text search in its most basic sense.

Your application's search interface may require more advanced search features, such as faceting or filtering. However, almost all applications with search allow full-text search, so the code presented here is widely applicable. Additional search features can be layered into the query generation process by sending additional input along with the query string as part of your search API.

</div>

That's why it's worth the time to build a simple query parser. Here's some advantages:

* Limit queries to the features _you_ need
* Handle expensive queries up front (for example, by limiting the number of terms that can be searched for)
* Better and faster error feedback for users
* Allows programmatic modification of search queries before running them (applications include query optimization, synonym expansion, spelling correction, or removing problematic characters)
* Build in heuristics specific to your application that are not possible for a general-purpose parser

In this tutorial, I'll be walking through the creation of a query parser using the Ruby library [Parslet](http://kschiess.github.io/parslet/) that can generate queries for the Elasticsearch query DSL. Our query parser will be more limited than the syntax supported by `SimpleQueryParser`, but the syntax is controlled by _our_ code now, so we can add new features if _we_ need to.

## Building a term-based query parser

At first, the query parser will be extremely limited. Given input like <span class="query-string">cat in the hat</span> it will be able to generate this Elasticsearch query:

```json
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
```

This is a [match](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-match-query.html) query, which does not interpret its input. You may notice that...we could just take the user input and put it in JSON structure. But we need to start somewhere!

### Defining a query language grammar with BNF

First, let's define a grammar for our simple query language using [Backus–Naur form](https://en.wikipedia.org/wiki/Backus%E2%80%93Naur_form) (BNF).

```
<query> ::= <term> | <query>
<term> ::= <alphanumeric> | <term>
```

Where `alphanumeric` is defined as the characters `[a-zA-Z0-9]`. The definitions are recursive to allow repetition. A [railroad diagram](https://en.wikipedia.org/wiki/Syntax_diagram) helps visualize the syntax.

#### Query

    {{svg="term-query.svg"}}

#### Term

    {{svg="term.svg"}}

### Defining a grammar with Parslet

<div class="aside">

### Aside: PEG parsing in other languages

This tutorial uses Ruby, but there are great, easy-to-use PEG parsing libraries available for most languages. JavaScript has [PEG.js](https://pegjs.org/), Python has [Arpeggio](http://www.igordejanovic.net/Arpeggio/) and [Parsimonious](https://github.com/erikrose/parsimonious#a-little-about-peg-parsers), and Java has [Parboiled](https://github.com/sirthias/parboiled/wiki).

</div>

BNF describes a [context-free grammar](https://en.wikipedia.org/wiki/Context-free_grammar) (CFG), which is a set of rules that can be used to generate any legal expression of the language. Because of its origins in natural, human languages, CFGs can be ambiguous. Parsing CFGs in the general case is slow (The best known algorithms for parsing CFGs run in <em>O(n<sup>3</sup>)</em> time). This makes CFGs inappropriate for machine-oriented languages. Therefore, [various](https://en.wikipedia.org/wiki/Deterministic_context-free_language) [limitations](https://en.wikipedia.org/wiki/LL_grammar) must be observed to avoid ambiguity and poor performance (despite this, [ambiguous parse trees still happen](https://en.wikipedia.org/wiki/Dangling_else)). 

Building a parser with traditional tools means defining a generative grammar with BNF (or, more likely, [extended BNF](https://en.wikipedia.org/wiki/Extended_Backus%E2%80%93Naur_form)), writing a lexer to convert input into tokens, and then feeding the tokens into a parser generator. 

The [Parsing Expression Grammar](https://en.wikipedia.org/wiki/Parsing_expression_grammar) (PEG) model makes parsers easier to write by eliminating the separate lexing step. In practice, a PEG parser _looks_ like an executable BNF grammar, but PEGs are _recognition-based_ rather than _generative_ like CFGs. 

Parsing expression grammars have the following characteristics:

* Cannot be ambiguous: the first alternative that matches is always chosen
* Operators consume as much input as matches and do not backtrack
* Allows infinite amount of look-ahead
* Can be parsed in linear time with memoization

[Parslet](http://kschiess.github.io/parslet/) is a Ruby library for generating PEG-style parsers. You define the rules of your grammar, and Parslet creates a parser that returns a parse tree for input. Then you define a transformer that takes the parse tree and converts it to an abstract syntax tree (AST). Finally, your code evaluates the AST to produce a result.

    {{svg="parslet-diagram.svg"}}

To define a parser with Parslet, subclass `Parslet::Parser` and define rules, which are called atoms, the building blocks of your grammar:

```ruby
class MyParser < Parslet::Parser
  # match matches one character; repeat allows 1 or more repetitions
  rule(:term) { match('[a-zA-Z0-9]').repeat(1) } 

  rule(:space) { match('\s').repeat(1) }

  # >> means "followed by"; maybe is equivalent to repeat(0, 1)
  rule(:query) { (term >> space.maybe).repeat }

  # The root tells Parslet where to start parsing the input
  root(:query)
end
```
<div class="aside">
<h3>Aside: Using Parslet from the console</h3>

When you want to quickly test out a Parslet parser, you can `include Parslet` in `irb` to add its API:

```ruby
require 'parslet'
include Parslet

match('\d').repeat(1).parse("1234")
 => "1234"@0
 ```
</div>

Notice how rules can be used by other rules. They plain old Ruby objects.

Now that we have a parser, we can instantiate it and parse a string:

```ruby
MyParser.new.parse("hello parslet")
# => "hello parslet"@0
```

It doesn't look like much! But notice the `@0`. The result is a [Parslet::Slice](http://www.rubydoc.info/github/kschiess/parslet/Parslet/Slice), and `@0` indicates where in the input string the match occurred. This is really useful for more complicated parsers.

This humble parser is also capable of rejecting invalid input:

```ruby
MyParser.new.parse("hello, parslet")
# => Parslet::ParseFailed: Extra input after last repetition at line 1 char 6.
```

The error message pinpoints exactly which character violated the grammar. With the `#ascii_tree`, you can get more details.

```ruby
begin
  MyParser.new.parse("hello, parslet")
rescue Parslet::ParseFailed => e
  puts e.parse_failure_cause.ascii_tree
end
```

Prints:

```
Extra input after last repetition at line 1 char 6.
`- Failed to match sequence (TERM SPACE?) at line 1 char 6.
   `- Expected at least 1 of [a-zA-Z0-9] at line 1 char 6.
      `- Failed to match [a-zA-Z0-9] at line 1 char 6.
```

### Building a parse tree

The simple parser above can recognize strings that match the grammar, but can't do anything with it. Using `#as`, we can capture parts of the input that we want to keep and save them as a parse tree. Anything not named with `#as` is discarded.

We need to capture the terms and the overall query.

    {{code="term_parser.rb:6-11"}}

This produces a parse tree rooted at `:query` that contains a list of `:term` objects. The value of the `:term` is a `Parslet::Slice`, as we saw above.

```ruby
QueryParser.new.parse("cat in the hat")
# =>
{
  :query => [
    {:term => "cat"@0},
    {:term => "in"@4},
    {:term => "the"@7},
    {:term => "hat"@11}
  ]
}
```

Once you have defined your parse tree, you can create a [Parslet::Transform](http://www.rubydoc.info/gems/parslet/Parslet/Transform) to convert the parse tree into an abstract syntax tree; or in our case, an object that knows how to convert itself to the Elasticsearch query DSL.

A `Parslet::Transform` defines rules for matching part of the parse tree and converting it to something else. Walking up from the leaf nodes, the entire tree is consumed. For this parse tree, the transformation is simple: match a `:term` `Hash` and convert it to a `String`, then match an array of terms and instantiate a `Query` object:

    {{code="term_parser.rb:13-16"}}

`Query` is also simple. It stores its list of term Strings, and defines a `#to_elasticsearch` method that joins them back together again in the query DSL:

    {{code="term_parser.rb:19-38"}}

All together, we can now generate an Elasticsearch `match` query:

```ruby
parse_tree = QueryParser.new.parse("cat in the hat")
query = QueryTransformer.new.apply(parse_tree)
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
```

<div class="aside">

### Aside: Fields

You may have noticed the Elasticsearch queries are only searching one field, `title`. This keeps the example code simple. A real query generator would need to know the [mapping](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html)'s schema so it could, for example, search all `text` fields.
</div>

OK, that was fun, but this is a a roundabout way of generating a simple Elasticsearch query. So far, the code could be replaced with a simple `match` query to Elasticsearch. But we can build up from here.

## Boolean queries: should, must, and must not

Unlike the boolean logic you may be familiar with, Lucene-based systems define three types of boolean clauses: **should**, which means that a clause ought to match, but does not reject documents that don't; **must**, which requires documents match the clause; and **must not**, which requires documents do not match the clause. These correspond to "or", "and", and "not", respectively.

In a query language, that might look like <span class="query-string">cat -hat +cradle</span>. I like using `+` and `-` for this rather than `AND` and `OR` because I think it looks better and users are less likely to accidentally trigger dangling operators such as <span class="query-string">foo AND</span>.

To support boolean logic, we'll add a new entity to our parse tree: a clause. A clause has an optional operator (`+` or `-`) and a term.

    {{svg="boolean-term-clause.svg"}}

In Parslet, the new clause node can be defined like this:

    {{code="boolean_term_parser.rb:6-13"}}

Parsing a query yields a parse tree like this:

```ruby
QueryParser.new.parse("the +cat in the -hat")
# =>
{:query=>
  [{:clause=>{:term=>"the"@0}},
   {:clause=>{:operator=>"+"@4, :term=>"cat"@5}},
   {:clause=>{:term=>"in"@9}},
   {:clause=>{:term=>"the"@12}},
   {:clause=>{:operator=>"-"@16, :term=>"hat"@17}}]}
```

Transforming this parse tree into the Elasticsearch query DSL will be a little more complicated than the previous iteration, where we could use `match` directly. Elasticsearch supports several [compound queries](https://www.elastic.co/guide/en/elasticsearch/reference/current/compound-queries.html) that allow you to combine simpler queries in complicated ways. For our parser, we'll use the [`bool` query](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html). It looks like this:

```json
{
  "query": {
    "bool": {
      "should": [ list of queries that SHOULD match (OR) ],
      "must": [ list of queries that MUST match (AND)],
      "must_not": [ list of queries that MUST NOT match (NOT)]
    }
  }
}
```

Yes, the input to a `bool` query is more queries. This is why you can be overwhelmed by `query`, `query`, `query` when trying to understand the JSON of a complicated Elasticsearch query!

In order to transform the parse tree into an Elasticsearch bool query, let's define a few classes.

First `Operator` is a helper to convert `+`, `-`, or `nil` into `:must`, `:must_not`, or `:should`:

    {{code="boolean_term_parser.rb:22-35"}}

Next, `Clause` holds an `Operator` and a term (which is a `String`):

    {{code="boolean_term_parser.rb:37-44"}}

Finally, `Query` changes to take an `Array` of clauses and buckets them into `should`, `must`, and `must_not` for conversion to the Elasticsearch query DSL:

    {{code="boolean_term_parser.rb:46-87"}}

Using these classes, we can write a Parslet transformer to convert the parse tree to a `Query`:

    {{code="boolean_term_parser.rb:15-20"}}

Since a clause only has a single term, we can use Parslet's `subtree` to consume each `:clause` hash from the tree and convert them to `Clause` instances. Then `sequence` will consume the array of `Clause` objects to create the `Query`.

```ruby
parse_tree = QueryParser.new.parse('the +cat in the -hat')
query = QueryTransformer.new.apply(parse_tree)
query.to_elasticsearch
# =>
{:query=>
  {:bool=>
    {:should=>
      [{:match=>{:title=>{:query=>"the"}}},
       {:match=>{:title=>{:query=>"in"}}},
       {:match=>{:title=>{:query=>"the"}}}],
     :must=>[{:match=>{:title=>{:query=>"cat"}}}],
     :must_not=>[{:match=>{:title=>{:query=>"hat"}}}]}}}
```

Now we have a `bool` query ready to send to Elasticsearch!

The [companion source code to this tutorial](https://github.com/look/query-parser) includes a script that lets you input search queries and see the parse tree and generated Elasticsearch query DSL JSON.

```
$ bundle exec bin/parse BooleanTermParser

Welcome to the parser test console. Using BooleanTermParser.
Input a query string to see the generated Elasticsearch query DSL.
To exit, use Control-C or Control-D
Input query string:
```

Give it a try!

## Phrase queries

Another important feature for a query parser is to be able to match phrases. In Elasticsearch, this is done with a [match_phrase](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-match-query-phrase.html) query. A `match_phrase` query can be used as input for a `bool` query, just like we previously used the `match` query. In our query language, an example query might look like <span class="query-string">"cat in the hat" -green +ham</span>.

    {{svg="phrase-query.svg"}}

Building on the previous example, let's add rules for matching a phrase, defined as a sequence of one or more terms surrounded by quotation marks.

    {{code="phrase_parser.rb:7-16"}}

The parse tree for the example query looks like this:

```ruby
QueryParser.new.parse('"cat in the hat" -green +ham')
# =>
{:query=>
  [{:clause=>
     {:phrase=>
       [{:term=>"cat"@1},
        {:term=>"in"@5},
        {:term=>"the"@8},
        {:term=>"hat"@12}]}},
   {:clause=>{:operator=>"-"@17, :term=>"green"@18}},
   {:clause=>{:operator=>"+"@24, :term=>"ham"@25}}]}
```

To support phrases, the `Clause` object needs to know whether it is a term clause or a phrase clause. To do this, let's introduce separate classes for `TermClause` and `PhraseClause`:

    {{code="phrase_parser.rb:47-63"}}

Other than this change, the code stays quite similar to the boolean term query parser. `Query` now needs to operate on the clause level rather than the term level, and later when generating the `bool` queries, choose `match` or `match_phrase` depending on the type.

    {{code="phrase_parser.rb:65-139"}}

With these classes defined, `QueryTransformer` can take the parse tree and transform it into a `Query`:

    {{code="phrase_parser.rb:18-30"}}

Here is the Elasticsearch query it generates:

```ruby
parse_tree = QueryParser.new.parse('"cat in the hat" -green +ham')
query = QueryTransformer.new.apply(parse_tree)
query.to_elasticsearch
# =>
{:query=>
  {:bool=>
    {:should=>[{:match_phrase=>{:title=>{:query=>"cat in the hat"}}}],
     :must=>[{:match=>{:title=>{:query=>"ham"}}}],
     :must_not=>[{:match=>{:title=>{:query=>"green"}}}]}}}
```

You can try out the `PhraseParser` by running `bundle exec bin/parse PhraseParser`.

With these features, this is a respectable query parser. It supports a simple syntax that's easy to understand and hard to mess up, and more importantly, hard to abuse. From here, we could improve the query parser in many ways to make it more robust. For example, we could limit phrases to 4 terms or limit the total number of clauses to 10. Because we are parsing the query ourselves, we can make decisions about what gets sent to Elasticsearch in an intelligent way that won't cause broken queries.

## Going beyond generic query parsers: Adding heuristics

So far, what we've built has been aimed at providing a simple user experience&mdash;and preventing harmful queries. However, another benefit of building your own query parser is that it is specific to your application, so you can tailor it to your domain.

For example, let's say we are building search for a database of books. We know a lot about the data, and can develop heuristics for users' search input. Let's say that we know all publication dates for books in the catalog are from the twentieth and early twenty-first century. We can turn a search term like <span class="query-string">1970</span> or <span class="query-string">1970s</span> into a date range query for the dates 1970 to 1979.

For the search <span class="query-string">cats 1970s</span> the Elasticsearch query DSL we want to generate is:

```json
{
  "query": {
    "bool": {
      "should": [
        {
          "match": {
            "title": {
              "query": "cats"
            }
          }
        },
        {
          "range": {
            "publication_year": {
              "gte": 1970,
              "lte": 1979
            }
          }
        }
      ]
    }
  }
}
```

To represent this in our grammar, we'll add a new clause type called `decade`.

    {{svg="heuristic-query.svg"}}

Where `decade` is defined as:

    {{svg="decade.svg"}}

To implement this, we add the new `decade` rule to the parser and use it in the `clause` rule.

    {{code="heuristic_parser.rb:7-21"}}

A PEG parser always takes the first alternative, so we need to make `decade` match before `term`, because a `decade` is always a valid `term`. If we didn't do this, the `decade` rule would never match.

For the transformer, we define a `DateRangeClause` class that takes a number and converts it into a start and end date:

    {{code="heuristic_parser.rb:71-79"}}

Finally, we add a `date_range` method to the `Query` class that converts a `DateRangeClause` into the Elasticsearch query DSL.

    {{code="heuristic_parser.rb:152-161"}}

Here is the Elasticsearch query DSL it generates:

```ruby
parse_tree = QueryParser.new.parse('cats "in the hat" 1970s')
query = QueryTransformer.new.apply(parse_tree)
query.to_elasticsearch
#=> {:query=>
  {:bool=>
    {:should=>
      [{:match=>{:title=>{:query=>"cats"}}},
       {:match_phrase=>{:title=>{:query=>"in the hat"}}},
       {:range=>{:publication_year=>{:gte=>1970, :lte=>1979}}}]}}}
```

You can try out the `HeuristicParser` by running `bundle exec bin/parse HeuristicParser`.

Now, thanks to Parslet, we have created a query parser that's purpose-built for our application. We fully control the syntax and Elasticsearch queries it makes, and we can add more heuristics that make sense for our application, but would never be part of a general-purpose query parser.

## Next steps

You can take the code in many directions from here. Here's some ideas.

### Improving search relevance

Our query parser does not need to be limited to a 1-to-1 correspondence with Elasticsearch. You may be able to improve search relevance by issuing the same query different ways. For example, the query <span class="query-string">cat in the hat</span> should match documents containing that text _as a phrase_ higher than documents containing the terms _individually_. You can implement this by creating a `bool` query with a `match_phrase` clause along with the `match` clauses for the individual terms.

### Error handling, reporting, and fallback

The current query parser raises an exception if the query can't be parsed. You can catch this in your application before sending the query to Elasticsearch and report the error the user. For a more user-friendly solution, you could try to correct the error in the input and re-parse or fallback to a simple `match` query when the input cannot be parsed.

### Limiting query complexity

We talked about limiting expensive queries, but the current parser doesn't do that yet. There are a few things to consider:

* Total number of clauses
* Number of words to allow in a phrase
* Overall query length

### Field configuration for query generation

To be truly useful, the query generator needs to know the schema of the [mapping](https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping.html) it is building Elasticsearch query DSL for. In the example code, we hard-coded a `text` field called `title` and an `integer` field called `publication_year`. A real schema will probably have many more fields.

Additional field types open up new search opportunities, too. Imagine your mapping has a [`keyword`](https://www.elastic.co/guide/en/elasticsearch/reference/current/keyword.html) field called `sku` for storing the exact text of SKUs. By adding SKU detection to the query parser, you could generate a [`term`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-term-query.html) query clause for the `sku` field when a user types in an SKU.

## Further reading

Here are some great resources for learning more about Parslet.

* The [Parslet documentation](http://kschiess.github.io/parslet/documentation.html) is an excellent resource, including a three part tutorial on building a simple interpreter.
* Nathan Witmer's [four part series on parsing TOML with Parslet](https://zerowidth.com/2013/02/24/parsing-toml-in-ruby-with-parslet.html) is a great introduction to its features.

To learn more about parsing, check out the following resources:

* [The language of languages](http://matt.might.net/articles/grammars-bnf-ebnf/) by Matt Might
* [Parsing Expression Grammars: A Recognition-Based Syntactic Foundation](http://bford.info/pub/lang/peg.pdf) by Bryan Ford is the original paper formalizing PEG parsers
* [PEG: Ambiguity, precision and confusion](https://jeffreykegler.github.io/Ocean-of-Awareness-blog/individual/2015/03/peg.html) by Jeffrey Kegler describes some of the tricky problems with PEG parsers
* [Mouse: from Parsing Expressions to a practical parser](http://mousepeg.sourceforge.net/) has a good discussion about PEG and packrat parsing
* [Crafting an interpreter Part 1 - Parsing and Grammars](https://www.codeproject.com/Articles/10115/Crafting-an-interpreter-Part-Parsing-and-Grammar) builds a PEG parser in C++ and has discussion about performance and ease of use

## Footnotes

<div id="fn1"><a href="#fn1-body"><sup>1</sup></a> OK, it was me.</div>

<hr>

_Thanks to [Marshall Scorcio](https://twitter.com/marshallscorcio), [Natthu Bharambe](https://www.facebook.com/natthu), and [Quin Hoxie](http://qhoxie.com/) for reviewing drafts of this tutorial. All errors are my own._

_Additional thanks to [Kaspar Schiess](http://www.absurd.li/) for creating Parslet and [Tab Atkins](http://www.xanthir.com/) for his [terrific railroad diagram generator](https://github.com/tabatkins/railroad-diagrams)._
