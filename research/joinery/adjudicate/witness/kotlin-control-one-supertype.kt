package kotlin.collections

private object EmptyMap : Serializable {
    private const val serialVersionUID: Long = 8246714829545688274

    override fun equals(other: Any?): Boolean = other is Map<*, *>
}
