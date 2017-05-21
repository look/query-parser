# Build a query parser
By [Luke Francl](http://www.recursion.org) ([look@recursion.org](mailto:look@recursion.org)), XXX 2017

## DRAFT Please do not distribute

More than a few times in my career, I've been part of a project that needed search. A Lucene-based search engine fits the bill. Usually somebody<sup>[[1](#fn1)]</sup> finds the search engine's built-in query parser, wires it up and that is that. It seems like a good idea and saves time up-front. But in the long run, it's better to write your own query parser.

## Problems with generic query parsers

Most search engines have a very powerful query parser built in, which can take a string and convert it to the underlying query objects. I'm most familiar with Lucene's query parser which is exposed by [Solr](https://wiki.apache.org/solr/SolrQuerySyntax) and [Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html), but other search APIs provide similar functionality (for example, [Google Cloud Platform's search API](https://cloud.google.com/appengine/docs/standard/python/search/query_strings)).

Exposing this interface directly to users has problems.

### User input may contain special characters

The built-in query parser has its own syntax, which users may not understand. For example, [Elasticsearch's `query_string` syntax reserves](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html#_reserved_characters) `+`, `-`, `=`, `&&`, `||`, `>`, `<`, `!`, `(`, `)`, `{`, `}`, `[`, `]`, `^`, `\"`, `~`, `*`, `?`, `:`, `\`, and `/`.

Using the syntax incorrectly will either trigger an error or lead to unexpected results. For example, the user query `title:cat "cat:hat"` should be escaped as `title\:cat "cat:hat"`. Escaping characters in a query string with regular expressions ranges from difficult to impossible.

Also, some characters [can't be escaped](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html#_reserved_characters):

> `<` and `>` can’t be escaped at all. The only way to prevent them from attempting to create a range query is to remove them from the query string entirely.

### Intentionally or unintentionally triggering advanced query features

Related to the above point, users can intentionally or unintentionally trigger advanced query features. For example, limiting a search term to a single field with `field_name:term` or boosting a term with `term^10`. The results range from confusing to malicious.

These operators can cause **very** expensive queries. In Lucene-based tools, [certain queries are very expensive](https://lucene.apache.org/core/6_5_0/core/org/apache/lucene/search/AutomatonQuery.html), because they require enumerating terms from the term dictionary in order to generate the query. A query with wildcards (especially a leading wildcard!) or regular expression [will do this](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html#_regular_expressions):

> A query string such as the following would force Elasticsearch to visit every term in the index:
>
> `/.*n/`
>
> Use with caution!

Range queries may seem harmless, but they [also have this problem](http://george-stathis.com/2013/10/18/setting-the-booleanquery-maxclausecount-in-elasticsearch/) (beware range queries on wide ranges of high resolution data!).

### Huge number of terms

Passing a user input directly to the query parser can be dangerous for more prosaic reasons. For example, the user may simply enter a large number of terms. This will generate a query with many clauses, which will take longer to execute. Truncating the query string is a simple work around, but if you truncate in the middle of an expression (for example, by breaking a quoted phrase or parenthetical expression), it could lead to an invalid query.

## Avoiding the foot gun

Lucene 4.7 added a new `SimpleQueryParser` that improved things quite a bit. In Elasticsearch, [this is available as `simple_query_string`](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-simple-query-string-query.html) in the search DSL. Unlike `query_string`, `simple_query_string` is designed to be exposed to end users and reduces the complexity of queries that can be created.

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

At first, the query parser will be extremely limited. Given input like "cat in the hat" it will be able to generate this Elasticsearch query:

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

This is a [match](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-match-query.html) query, which does not interpret its input. You may notice that...we could just take the user input and put it in JSON structure. But we need to start somewhere!

### Defining a grammar

First, let's define a grammar for our simple query language using [Backus–Naur form](https://en.wikipedia.org/wiki/Backus%E2%80%93Naur_form) (BNF).

```
<query> ::= <term> | <query>
<term> ::= <alphanumeric> | <term>
```

Where `alphanumeric` is defined as the characters `[a-zA-Z0-9]`. The definitions are recursive to allow repetition. A [railroad diagram](https://en.wikipedia.org/wiki/Syntax_diagram) helps visualize the syntax.

#### Query

<svg class="railroad-diagram" width="180" height="92" viewBox="0 0 180 92">
<g transform="translate(.5 .5)">
<path d="M 20 21 v 20 m 10 -20 v 20 m -10 -10 h 20.5"></path>
<g>
<path d="M40 31h0"></path>
<path d="M140 31h0"></path>
<path d="M40 31h20"></path>
<g class="non-terminal">
<path d="M60 31h4"></path>
<path d="M116 31h4"></path>
<rect x="64" y="20" width="52" height="22"></rect>
<text x="90" y="35">term</text>
</g>
<path d="M120 31h20"></path>
<path d="M40 31a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="non-terminal">
<path d="M60 61h0"></path>
<path d="M120 61h0"></path>
<rect x="60" y="50" width="60" height="22"></rect>
<text x="90" y="65">query</text>
</g>
<path d="M120 61a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M 140 31 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
</svg>


#### Term

<svg class="railroad-diagram" width="236" height="92" viewBox="0 0 236 92">
<g transform="translate(.5 .5)">
<path d="M 20 21 v 20 m 10 -20 v 20 m -10 -10 h 20.5"></path>
<g>
<path d="M40 31h0"></path>
<path d="M196 31h0"></path>
<path d="M40 31h20"></path>
<g class="terminal">
<path d="M60 31h0"></path>
<path d="M176 31h0"></path>
<rect x="60" y="20" width="116" height="22" rx="10" ry="10"></rect>
<text x="118" y="35">alphanumeric</text>
</g>
<path d="M176 31h20"></path>
<path d="M40 31a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="non-terminal">
<path d="M60 61h32"></path>
<path d="M144 61h32"></path>
<rect x="92" y="50" width="52" height="22"></rect>
<text x="118" y="65">term</text>
</g>
<path d="M176 61a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M 196 31 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
</svg>

## Defining a grammar with Parslet

BNF defines the rules for a generative grammar for a context-free language, which means it can be ambiguous. Parsing algorithms transform the grammar into a parser that can produce a parse tree, with special cases to handle the ambiguity of a context-free grammar. 

Another way of parsing is to start with an analytic grammar. The [Parsing Expression Grammar](https://en.wikipedia.org/wiki/Parsing_expression_grammar) (PEG) looks like BNF, but the choice operator always picks the first match. PEGs cannot be ambiguous.

[Parslet](http://kschiess.github.io/parslet/) is a Ruby library for generating PEG-style parsers. You define the rules of your grammar, and Parslet creates a parser that returns a parse tree for input. Then you define a transformer that takes the parse tree and converts it to an abstract syntax tree (AST). Finally, your code evaluates the AST to produce a result.

```
Parslet::Parser => Parses input, returns parse tree
Parslet::Transformer => Transforms parse tree into Abstract Syntax Tree
Your code => evaluate AST to produce a result
```

**XXX** Make a diagram of the above?

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

```
MyParser.new.parse("hello parslet")
# => "hello parslet"@0
```

It doesn't look like much! But notice the `@0`. The result is a [Parslet::Slice](http://www.rubydoc.info/github/kschiess/parslet/Parslet/Slice), and `@0` indicates where in the input string the match occurred. This is really useful for more complicated parsers.

This humble parser is also capable of rejecting invalid input:

```
MyParser.new.parse("hello, parslet")
# => Parslet::ParseFailed: Extra input after last repetition at line 1 char 6.
```

The error message pinpoints exactly which character violated the grammar. With the `#ascii_tree`, you can get more details.

```
begin
  MyParser.new.parse("hello, parslet")
rescue Parslet::ParseFailed => e
  puts e.cause.ascii_tree
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

**XXX** NEED TO TALK ABOUT FIELDS! This example uses `title` hard-coded. Where'd that come from?

OK, that was fun, but this is a a roundabout way of generating a simple Elasticsearch query. So far, the code could be replaced with a simple `match` query to Elasticsearch. But we can build up from here.

## Boolean queries: should, must, and must not

Unlike the boolean logic you may be familiar with, Lucene-based systems define three types of boolean clauses: **should**, which means that a clause ought to match, but does not reject documents that don't; **must**, which requires documents match the clause; and **must not**, which requires documents do not match the clause. These correspond to "or", "and", and "not", respectively.

In a query language, that might look like this: `cat -hat +cradle`. I like using `+` and `-` for this rather than `AND` and `OR` because I think it looks better and users don't have to worry about dangling clauses (for example, `foo AND`).

To support boolean logic, we'll add a new entity to our parse tree: a clause. A clause has an optional operator (`+` or `-`) and a term.

<svg class="railroad-diagram" width="290" height="120" viewBox="0 0 290 120">
<g transform="translate(.5 .5)">
<path d="M 20 21 v 20 m 10 -20 v 20 m -10 -10 h 20.5"></path>
<path d="M40 31h10"></path>
<g>
<path d="M50 31h0"></path>
<path d="M240 31h0"></path>
<path d="M50 31h10"></path>
<g>
<path d="M60 31h0"></path>
<path d="M230 31h0"></path>
<g>
<path d="M60 31h0"></path>
<path d="M168 31h0"></path>
<path d="M60 31h20"></path>
<g>
<path d="M80 31h68"></path>
</g>
<path d="M148 31h20"></path>
<path d="M60 31a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M80 51h0"></path>
<path d="M148 51h0"></path>
<path d="M80 51h20"></path>
<g class="terminal">
<path d="M100 51h0"></path>
<path d="M128 51h0"></path>
<rect x="100" y="40" width="28" height="22" rx="10" ry="10"></rect>
<text x="114" y="55">-</text>
</g>
<path d="M128 51h20"></path>
<path d="M80 51a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal">
<path d="M100 81h0"></path>
<path d="M128 81h0"></path>
<rect x="100" y="70" width="28" height="22" rx="10" ry="10"></rect>
<text x="114" y="85">+</text>
</g>
<path d="M128 81a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M148 51a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<path d="M168 31h10"></path>
<g class="non-terminal">
<path d="M178 31h0"></path>
<path d="M230 31h0"></path>
<rect x="178" y="20" width="52" height="22"></rect>
<text x="204" y="35">term</text>
</g>
</g>
<path d="M230 31h10"></path>
<path d="M60 31a10 10 0 0 0 -10 10v49a10 10 0 0 0 10 10"></path>
<g>
<path d="M60 100h170"></path>
</g>
<path d="M230 100a10 10 0 0 0 10 -10v-49a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M240 31h10"></path>
<path d="M 250 31 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
</svg>


In Parslet, the new clause node can be defined like this:

    {{code="boolean_term_parser.rb:6-13"}}

Parsing a query yields a parse tree like this:

```
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

**XXX** Add a script that readers can run to execute queries?

## Phrase queries

Another important feature for a query parser is to be able to match phrases. In Elasticsearch, this is done with a [match_phrase](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-match-query-phrase.html) query. A `match_phrase` query can be used as input for a `bool` query, just like we previously used the `match` query. In our query language, an example query might look like:

    "cat in the hat" -green +ham

<svg class="railroad-diagram" width="436" height="120" viewBox="0 0 436 120">
<g transform="translate(.5 .5)">
<path d="M 20 21 v 20 m 10 -20 v 20 m -10 -10 h 20.5"></path>
<path d="M40 31h10"></path>
<g>
<path d="M50 31h0"></path>
<path d="M386 31h0"></path>
<path d="M50 31h10"></path>
<g>
<path d="M60 31h0"></path>
<path d="M376 31h0"></path>
<g>
<path d="M60 31h0"></path>
<path d="M168 31h0"></path>
<path d="M60 31h20"></path>
<g>
<path d="M80 31h68"></path>
</g>
<path d="M148 31h20"></path>
<path d="M60 31a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M80 51h0"></path>
<path d="M148 51h0"></path>
<path d="M80 51h20"></path>
<g class="terminal">
<path d="M100 51h0"></path>
<path d="M128 51h0"></path>
<rect x="100" y="40" width="28" height="22" rx="10" ry="10"></rect>
<text x="114" y="55">-</text>
</g>
<path d="M128 51h20"></path>
<path d="M80 51a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal">
<path d="M100 81h0"></path>
<path d="M128 81h0"></path>
<rect x="100" y="70" width="28" height="22" rx="10" ry="10"></rect>
<text x="114" y="85">+</text>
</g>
<path d="M128 81a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M148 51a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<g>
<path d="M168 31h0"></path>
<path d="M376 31h0"></path>
<path d="M168 31h20"></path>
<g class="non-terminal">
<path d="M188 31h58"></path>
<path d="M298 31h58"></path>
<rect x="246" y="20" width="52" height="22"></rect>
<text x="272" y="35">term</text>
</g>
<path d="M356 31h20"></path>
<path d="M168 31a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g>
<path d="M188 61h0"></path>
<path d="M356 61h0"></path>
<g class="terminal">
<path d="M188 61h0"></path>
<path d="M216 61h0"></path>
<rect x="188" y="50" width="28" height="22" rx="10" ry="10"></rect>
<text x="202" y="65">"</text>
</g>
<path d="M216 61h10"></path>
<path d="M226 61h10"></path>
<g>
<path d="M236 61h0"></path>
<path d="M308 61h0"></path>
<path d="M236 61h10"></path>
<g class="non-terminal">
<path d="M246 61h0"></path>
<path d="M298 61h0"></path>
<rect x="246" y="50" width="52" height="22"></rect>
<text x="272" y="65">term</text>
</g>
<path d="M298 61h10"></path>
<path d="M246 61a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M246 81h52"></path>
</g>
<path d="M298 81a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M308 61h10"></path>
<path d="M318 61h10"></path>
<g class="terminal">
<path d="M328 61h0"></path>
<path d="M356 61h0"></path>
<rect x="328" y="50" width="28" height="22" rx="10" ry="10"></rect>
<text x="342" y="65">"</text>
</g>
</g>
<path d="M356 61a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
</g>
<path d="M376 31h10"></path>
<path d="M60 31a10 10 0 0 0 -10 10v49a10 10 0 0 0 10 10"></path>
<g>
<path d="M60 100h316"></path>
</g>
<path d="M376 100a10 10 0 0 0 10 -10v-49a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M386 31h10"></path>
<path d="M 396 31 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
</svg>

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

**XXX** Again, give readers a script they can use to execute queries


With these features, this is a respectable query parser. It supports a simple syntax that's easy to understand and hard to mess up, and more importantly, hard to abuse. From here, we could improve the query parser in many ways to make it more robust. For example, we could limit phrases to 4 terms or limit the total number of clauses to 10. Because we are parsing the query ourselves, we can make decisions about what gets sent to Elasticsearch in an intelligent way that won't cause broken queries.

## Going beyond generic query parsers: Adding heuristics

So far, what we've built has been aimed at providing a simple user experience -- and preventing harmful queries. However, another benefit of building your own query parser is that it is specific to your application, so you can tailor it to your domain.

For example, let's say we are building search for a database of books. We know a lot about the data, and can develop heuristics for users' search input. Let's say that we know all publication dates for books in the catalog are from the twentieth and early twenty-first century. We can turn a search term like "1970" or "1970s" into a date range query for the dates 1970 - 1979.

For the search `cats 1970s` the Elasticsearch query DSL we want to generate is:

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

<svg class="railroad-diagram" width="436" height="139" viewBox="0 0 436 139">
<g transform="translate(.5 .5)">
<path d="M 20 21 v 20 m 10 -20 v 20 m -10 -10 h 20.5"></path>
<path d="M40 31h10"></path>
<g>
<path d="M50 31h0"></path>
<path d="M386 31h0"></path>
<path d="M50 31h10"></path>
<g>
<path d="M60 31h0"></path>
<path d="M376 31h0"></path>
<g>
<path d="M60 31h0"></path>
<path d="M168 31h0"></path>
<path d="M60 31h20"></path>
<g>
<path d="M80 31h68"></path>
</g>
<path d="M148 31h20"></path>
<path d="M60 31a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M80 51h0"></path>
<path d="M148 51h0"></path>
<path d="M80 51h20"></path>
<g class="terminal">
<path d="M100 51h0"></path>
<path d="M128 51h0"></path>
<rect x="100" y="40" width="28" height="22" rx="10" ry="10"></rect>
<text x="114" y="55">-</text>
</g>
<path d="M128 51h20"></path>
<path d="M80 51a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="terminal">
<path d="M100 81h0"></path>
<path d="M128 81h0"></path>
<rect x="100" y="70" width="28" height="22" rx="10" ry="10"></rect>
<text x="114" y="85">+</text>
</g>
<path d="M128 81a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M148 51a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
</g>
<g>
<path d="M168 31h0"></path>
<path d="M376 31h0"></path>
<path d="M168 31h20"></path>
<g class="non-terminal">
<path d="M188 31h50"></path>
<path d="M306 31h50"></path>
<rect x="238" y="20" width="68" height="22"></rect>
<text x="272" y="35">decade</text>
</g>
<path d="M356 31h20"></path>
<path d="M168 31a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g class="non-terminal">
<path d="M188 61h58"></path>
<path d="M298 61h58"></path>
<rect x="246" y="50" width="52" height="22"></rect>
<text x="272" y="65">term</text>
</g>
<path d="M356 61a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
<path d="M168 31a10 10 0 0 1 10 10v40a10 10 0 0 0 10 10"></path>
<g>
<path d="M188 91h0"></path>
<path d="M356 91h0"></path>
<g class="terminal">
<path d="M188 91h0"></path>
<path d="M216 91h0"></path>
<rect x="188" y="80" width="28" height="22" rx="10" ry="10"></rect>
<text x="202" y="95">"</text>
</g>
<path d="M216 91h10"></path>
<path d="M226 91h10"></path>
<g>
<path d="M236 91h0"></path>
<path d="M308 91h0"></path>
<path d="M236 91h10"></path>
<g class="non-terminal">
<path d="M246 91h0"></path>
<path d="M298 91h0"></path>
<rect x="246" y="80" width="52" height="22"></rect>
<text x="272" y="95">term</text>
</g>
<path d="M298 91h10"></path>
<path d="M246 91a10 10 0 0 0 -10 10v0a10 10 0 0 0 10 10"></path>
<g>
<path d="M246 111h52"></path>
</g>
<path d="M298 111a10 10 0 0 0 10 -10v0a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M308 91h10"></path>
<path d="M318 91h10"></path>
<g class="terminal">
<path d="M328 91h0"></path>
<path d="M356 91h0"></path>
<rect x="328" y="80" width="28" height="22" rx="10" ry="10"></rect>
<text x="342" y="95">"</text>
</g>
</g>
<path d="M356 91a10 10 0 0 0 10 -10v-40a10 10 0 0 1 10 -10"></path>
</g>
</g>
<path d="M376 31h10"></path>
<path d="M60 31a10 10 0 0 0 -10 10v68a10 10 0 0 0 10 10"></path>
<g>
<path d="M60 119h316"></path>
</g>
<path d="M376 119a10 10 0 0 0 10 -10v-68a10 10 0 0 0 -10 -10"></path>
</g>
<path d="M386 31h10"></path>
<path d="M 396 31 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
</svg>

Where `decade` is defined as:

<svg class="railroad-diagram" width="412" height="101" viewBox="0 0 412 101">
<g transform="translate(.5 .5)">
<path d="M 20 30 v 20 m 10 -20 v 20 m -10 -10 h 20.5"></path>
<path d="M40 40h10"></path>
<g>
<path d="M50 40h0"></path>
<path d="M362 40h0"></path>
<g>
<path d="M50 40h0"></path>
<path d="M166 40h0"></path>
<path d="M50 40h20"></path>
<g>
<path d="M70 40h0"></path>
<path d="M146 40h0"></path>
<g class="terminal">
<path d="M70 40h0"></path>
<path d="M98 40h0"></path>
<rect x="70" y="29" width="28" height="22" rx="10" ry="10"></rect>
<text x="84" y="44">1</text>
</g>
<path d="M98 40h10"></path>
<path d="M108 40h10"></path>
<g class="terminal">
<path d="M118 40h0"></path>
<path d="M146 40h0"></path>
<rect x="118" y="29" width="28" height="22" rx="10" ry="10"></rect>
<text x="132" y="44">9</text>
</g>
</g>
<path d="M146 40h20"></path>
<path d="M50 40a10 10 0 0 1 10 10v10a10 10 0 0 0 10 10"></path>
<g>
<path d="M70 70h0"></path>
<path d="M146 70h0"></path>
<g class="terminal">
<path d="M70 70h0"></path>
<path d="M98 70h0"></path>
<rect x="70" y="59" width="28" height="22" rx="10" ry="10"></rect>
<text x="84" y="74">2</text>
</g>
<path d="M98 70h10"></path>
<path d="M108 70h10"></path>
<g class="terminal">
<path d="M118 70h0"></path>
<path d="M146 70h0"></path>
<rect x="118" y="59" width="28" height="22" rx="10" ry="10"></rect>
<text x="132" y="74">0</text>
</g>
</g>
<path d="M146 70a10 10 0 0 0 10 -10v-10a10 10 0 0 1 10 -10"></path>
</g>
<path d="M166 40h10"></path>
<g class="terminal">
<path d="M176 40h0"></path>
<path d="M236 40h0"></path>
<rect x="176" y="29" width="60" height="22" rx="10" ry="10"></rect>
<text x="206" y="44">&#91;0-9&#93;</text>
</g>
<path d="M236 40h10"></path>
<path d="M246 40h10"></path>
<g class="terminal">
<path d="M256 40h0"></path>
<path d="M284 40h0"></path>
<rect x="256" y="29" width="28" height="22" rx="10" ry="10"></rect>
<text x="270" y="44">0</text>
</g>
<path d="M284 40h10"></path>
<g>
<path d="M294 40h0"></path>
<path d="M362 40h0"></path>
<path d="M294 40a10 10 0 0 0 10 -10v0a10 10 0 0 1 10 -10"></path>
<g>
<path d="M314 20h28"></path>
</g>
<path d="M342 20a10 10 0 0 1 10 10v0a10 10 0 0 0 10 10"></path>
<path d="M294 40h20"></path>
<g class="terminal">
<path d="M314 40h0"></path>
<path d="M342 40h0"></path>
<rect x="314" y="29" width="28" height="22" rx="10" ry="10"></rect>
<text x="328" y="44">s</text>
</g>
<path d="M342 40h20"></path>
</g>
</g>
<path d="M362 40h10"></path>
<path d="M 372 40 h 20 m -10 -10 v 20 m 10 -20 v 20"></path>
</g>
</svg>

To implement this, we add the new `decade` rule to the parser and use it in the `clause` rule.

    {{code="heuristic_parser.rb:7-21"}}

A PEG parser always takes the first alternative, so we need to make `decade` match before `term`, because a `decade` is always a valid `term`. If we didn't do this, the `decade` rule would never match.

For the transformer, we define a `DateRangeClause` class that takes a number and converts it into a start and end date:

    {{code="heuristic_parser.rb:71-79"}}

Finally, we add a `date_range` method to the `Query` class that converts a `DateRangeClause` into the Elasticsearch query DSL.

    {{code="heuristic_parser.rb:152-161"}}

Here is the Elasticsearch query DSL it generates:

```
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

Now, thanks to Parslet, we have created a query parser that's purpose-built for our application. We fully control the syntax and Elasticsearch queries it makes, and we can add more heuristics that make sense for our application, but would never be part of a general-purpose query parser.

## Resources

**XXX:** Something about where to find the source code, how it's organized? Could also be an aside.

The parslet tutorial is an excellent resource.

Talk about Parslet: https://www.youtube.com/watch?v=ET_POMJNWNs

https://jeffreykegler.github.io/Ocean-of-Awareness-blog/individual/2015/03/peg.html

https://www.codeproject.com/Articles/10115/Crafting-an-interpreter-Part-Parsing-and-Grammar

http://matt.might.net/articles/grammars-bnf-ebnf/

https://github.com/tabatkins/railroad-diagrams

Original PEG paper http://bford.info/pub/lang/peg.pdf

<div id="fn1">[1] OK, it was me.</div>
