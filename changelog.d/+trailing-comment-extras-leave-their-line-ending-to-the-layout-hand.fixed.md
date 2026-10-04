Python's layout hand is asked again after an extra node passes. A trailing
comment therefore keeps its comment node and leaves its newline, indentation,
and dedentation visible to the parser. Anonymous whitespace retains the
existing progress rule, so consuming an answered newline does not invent an
additional statement ending at EOF.

The scanner convention check also recognizes the separately pinned TSX dialect
as sharing TypeScript's automatic semicolon hand.
