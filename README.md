# Build a query parser example code

This is example code for my tutorial [Build a query parser](http://www.recursion.org/query-parser/).

## How the code is organized

Each query parser is self-contained to make the tutorial easier to follow. This does mean there's a lot of duplication. In order to keep the classes separate, each query parser is contained in its own module.

The sequence of query parsers is:

1. [TermParser](https://github.com/look/query-parser/blob/master/term_parser.rb)
2. [BooleanTermParser](https://github.com/look/query-parser/blob/master/boolean_term_parser.rb)
3. [PhraseParser](https://github.com/look/query-parser/blob/master/phrase_parser.rb)
4. [HeuristicParser](https://github.com/look/query-parser/blob/master/heuristic_parser.rb)

## Installing and running

### Prerequisites

You will need Ruby (tested with 2.4) to run the query parsers and Java (tested with 1.8) to run Elasticsearch if you want to try out the parsers for real. I use RVM and jEnv to manage the versions, but you do not have to.

### Install dependencies

```
bundle install
```

### Run unit tests

```
bundle exec rake test
```

### Run integration tests

The integration tests require Elasticsearch to be started.

```
elasticsearch/bin/elasticsearch
```

In another terminal:

```
bundle exec rake integration_test
```

### Query generation console

The `parse` program allows you to test out the different parser and see the parse tree and Elasticsearch DSL that is generated based on a query string you provide.

To run it:

```
bundle exec bin/parse
```

The program defaults to the `HeuristicParser` because it is the most featureful. To try one of the others, provide it as a command-line argument:

```
bundle exec bin/parse BooleanTermParser
```

## License

The source code in this repository is released into the public domain.

The tutorial is under copyright and cannot be republished without my permission.
