Hidden zero-width scanner tokens now contribute their boundary to enclosing
reductions. An aliased Python match body starts at its indent token, while
nullable nonterminals still leave leading whitespace outside their parent.
