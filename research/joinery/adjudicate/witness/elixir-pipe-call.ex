defmodule Router do
  def group(map) do
    map
    |> then(fn {match_routes_exprs, rest} -> {rest, match_routes_exprs} end)
  end
end
