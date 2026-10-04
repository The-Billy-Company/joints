"""Parse grammar folios and run structural queries through libjnt.

Banks own parsers, parsers own trees and queries. Use nested context managers
for explicit release. Strict parsing rejects repairs and partial trees so CI
checks cannot mistake recovery for understood source.
"""

from ._api import (
    Bank,
    Capture,
    JointsError,
    Match,
    Node,
    ParseError,
    Parser,
    Query,
    Repair,
    Tree,
)

__version__ = "0.0.0"
__all__ = [
    "Bank",
    "Parser",
    "Tree",
    "Node",
    "Query",
    "Capture",
    "Match",
    "JointsError",
    "ParseError",
    "Repair",
    "__version__",
]
