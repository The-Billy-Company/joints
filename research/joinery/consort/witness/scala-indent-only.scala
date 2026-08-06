object A:
  def f(x: Int): Int =
    val y = x + 1
    y * 2

  def g(x: Int): Int =
    f(x) + 1
