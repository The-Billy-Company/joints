The Python interface now opens grammar banks, reuses native parsers, traverses
nodes, and executes structural queries through libjnt. Strict parsing requires a
whole, unrepaired, sound tree before handing it to a CI consumer. Partial forests
remain available explicitly with their repair counts. Native integration checks
exercise real grammar bytes, predicates, UTF-8 locations, parser reuse, thread
affinity, and handle misuse. The native library is built separately; this does
not publish a platform wheel or migrate an existing linter frontend.
