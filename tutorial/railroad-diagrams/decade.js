Diagram(
    Sequence(
        Choice(0,
               Sequence(
                   Terminal('1'),
                   Terminal('9')
               ),
               Sequence(
                   Terminal('2'),
                   Terminal('0')
               )
              ),
        Terminal('[0-9]'),
        Terminal('0'),
        Optional(Terminal('s'))
    )
)
