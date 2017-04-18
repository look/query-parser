# Build a query parser

More than once in my career, I've been part of a project that needed search. Usually somebody[1] finds the search engine's built-in query parser, wires it up and that is that. It seems like a good idea and saves time upfront. But in the long run, it's better to write your own query parser.

## Problems with generic query parsers

Most search engines have a very powerful query parser built in, which can take a string and convert it to the underlying query objects. I'm most familar with Lucene's query parser which is exposed by [Solr](https://wiki.apache.org/solr/SolrQuerySyntax) and [Elasticsearch](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html), but other search APIs provide similar functionality (for example, [Google Cloud Platform's search API](https://cloud.google.com/appengine/docs/standard/python/search/query_strings)).

Exposing this interface directly to users has problems.

* User input can cause exceptions because the query syntaxes have special charaters. For Elasticsearch `query_string`:

> The reserved characters are: + - = && || > < ! ( ) { } [ ] ^ " ~ * ? : \ /

Special characters can be escaped, but what about when a character is in quotes? 

    title\:cat "cat:hat"
    
Escaping characters with regular expressions ranges from difficult to impossible (for example, ensuring balanced quotation marks).

Also, some characters can't be escaped:

> `<` and `>`` can’t be escaped at all. The only way to prevent them from attempting to create a range query is to remove them from the query string entirely.

* Users can intentionally or unintentionally trigger advanced query features. For example, limiting a search term to a single field with `field_name:term` or boosting a term with `term^10`. The can range from confusing to malicous.

* Users can intentionally or unintentionally cause **very** expensive queries. In Lucene-based tools, certain queries are very expensive, because they require enumerating terms from the term dctionary in order to generate the query. A query with wildcards (especially a leading wildcard!) or regular expression will do this:

> A query string such as the following would force Elasticsearch to visit every term in the index:
> 
> `/.*n/`
>
> Use with caution!

Range queries may seem harmless, but they also have this problem (beware range queries on wide ranges of high resolution data!).

More details: https://lucene.apache.org/core/6_5_0/core/org/apache/lucene/search/AutomatonQuery.html

* A query with a large number of terms can cause an expensive query. (Example: cloudflare automatic search)

Lucene 4.7 added a new `SimpleQueryParser` that improved things quite a bit (In Elasticsearch, this is available as `simple_query_string` in the search DSL). It is designed to be exposed to end users and reduces the complexity of queries that can be created.

But even `SimpleQueryParser` is quite powerful in ways you may not want. [Users can specify](http://lucene.apache.org/core/6_5_0/queryparser/org/apache/lucene/queryparser/simple/SimpleQueryParser.html):

> + signifies AND operation
> | signifies OR operation
> - negates a single token
> " wraps a number of tokens to signify a phrase for searching
> * at the end of a term signifies a prefix query
> ( and ) signify precedence
> ~N after a word signifies edit distance (fuzziness)
> ~N after a phrase signifies slop amount

Often, when you go down the built-in query parser route, you'll get something working quickly, but later run into problems. Users (or your exception monitoring software) complains that queries don't work; or extremely expensive queries slow the service down for everyone.

That's why it's worth the time to build a simple query parser. Here's some advantages:

* Limit queries to the features _you_ need
* Handle expensive queries up front (for example, by limiting the number of terms that can be searched for)
* Better and faster error feedback for users
* perform programmatic modification of search queries before running them (for example, synonym expansion, spelling correction, or removing problematic characters)
* Build in heuristics specific to your application that are not possible for a general-purpose parser (EXAMPLE: date parsing)


In this tutorial, I'll be walking through the creation of a query parser that can generate queries for the Elasticsearch query DSL. It will start simple, but build up to supporting terms, boolean operators (`-` and `+`), and phrases. This is a good 80% solution that will work well for most use cases. It's more limited than the syntax supported by `SimpleQueryParser`, but the syntax is controlled by _our_ code now, so we can add new features if _we_ need to.

## Simple term parser

The goal of this parser is to be able to generate a boolean query for one or more search terms[1]. In Elasticsearch, a boolean query can have three types of clauses: should, must, and must_not. These correspond to "or", "and", and "not". Each clause has a list of queries. In this example, we'll use a `match` query, which generates a boolean query after analyzing the search terms (analysis is necessary so that a search term matches what was indexed). Here's an sample `match` query on the `title` field[2]:


    {
      "query": {
        "match": {
          "title": {
            "query": "cat hat",
            "operator": "or"
          }
        }
      }
    }
    
Setting aside the analysis, the above query is equivalent to this lower-level boolean query with two term queries in a should clause:

    {
      "query": {
        "bool" : {
          "should" : [
            { "term" : { "title" : "cat" } },
            { "term" : { "title" : "hat" } }
          ]
        }
      }
    }


For the simple term parser, we'll take user input and create a `match` query[1]

To build the parser, I'll use [Parslet](http://kschiess.github.io/parslet/) which is a parser generator based on the [parsing expression grammar](https://en.wikipedia.org/wiki/Parsing_expression_grammar) (PEG) formalism. Ruby's standard library also includes racc which is a LALR parser generator similar to yacc, but Parslet is much easier to use and better documented.

First, I'll define the rules for a term query:

CODE


NOTE: build up from terms example? show parsing a string with it.

This means a search term is one or more [a-zA-Z0-9] character (feel free to extend this to match your use case). A query is at least one search term, followed by additional terms separated by spaces. Naming the components with `as` allows us to access them in the parse tree:

CODE


Diagram:

QUERY 
|    \
|     \
TERM   TERM *


Next, I'll define a transformer to convert this parse tree into something useful. Parslet Transformers start at the leaf nodes and work their way up. XXX. For the top-level `:query` node, I've defined a TermQuery class that takes a list of terms and knows how to convert itself into the Elasticsearch DSL.

OK, that was fun, but so far this could be replaced with a simple match query to Elasticsearch. Let's add boolean operators to the query language. I like using `+` and `-` for this rather than `AND` and `OR` because I think it looks better and users don't have to worry about dangling clauses (for example, "foo AND"). 

CODE

Now we need to transform this parse tree into an Elasticsearch boolean query. To do this, I've defined a `BooleanTermQuery` class with three arguments: 

To wrap up this tutorial, I'll add phrase queries. In elasticsearch, this is done with a match_phrase query. 

Example query: 

    hello -world +"sample phrase" -"do not match"

CODE


## Example: date heuristics

90s 90's 1990s 1990's 

We can use heuristics because we know the application's data. Date are all in the range 1950 - present, so quereis like "50s" are unabiguous. Let's expand them to date ranges between 1950-1960.

## Resources

The parslet tutorial is an excellent resource.

Talk about Parslet:
https://www.youtube.com/watch?v=ET_POMJNWNs

https://jeffreykegler.github.io/Ocean-of-Awareness-blog/individual/2015/03/peg.html
https://www.codeproject.com/Articles/10115/Crafting-an-interpreter-Part-Parsing-and-Grammar


[1] OK, it was me.

[1] see the accompanying repository for the sample data

[2] match query is actually sufficient to do this by itself. xxxxxx




