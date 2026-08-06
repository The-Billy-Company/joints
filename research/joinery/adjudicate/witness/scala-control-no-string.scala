case object None extends Option[Nothing] {
  def get: Nothing = throw new NoSuchElementException()
}
