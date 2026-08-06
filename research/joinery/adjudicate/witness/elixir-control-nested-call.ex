defmodule Router do
  def verify(routes_with_exprs) do
    Enum.uniq(Enum.map(routes_with_exprs, &elem(&1, 1)))
  end
end
