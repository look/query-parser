Diagram(
    OneOrMore(
        Sequence(
            Optional(
                Choice(0,
                       Terminal('-'),
                       Terminal('+')
                      ),
                'skip'),
            NonTerminal('term')
        )
    )
)
