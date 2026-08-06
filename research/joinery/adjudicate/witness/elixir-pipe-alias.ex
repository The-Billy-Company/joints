defmodule Router do
  def verify(routes_with_exprs) do
    routes_with_exprs
    |> Enum.map(&elem(&1, 1).path)
    |> Enum.uniq()
  end
end
