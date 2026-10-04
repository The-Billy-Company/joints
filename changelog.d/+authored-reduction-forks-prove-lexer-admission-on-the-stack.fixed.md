Lexer admission now follows authored reduction alternatives on the current parse
stack. An ambiguity alone no longer admits a layout token that every branch
would refuse. A separate bounded admission walk can discharge longer pending
reductions without changing supplied-token guesses; viable alternatives and
exhausted proof budgets keep their conservative admission.
