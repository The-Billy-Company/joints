struct ChunkedCollection {
  var base: String
  var firstUpperBound: String.Index

  init(base: String) {
    self.base = base
    firstUpperBound = endOfChunk(base.startIndex)
  }
}
