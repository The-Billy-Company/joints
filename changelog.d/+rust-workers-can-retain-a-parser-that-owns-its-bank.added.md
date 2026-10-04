`Bank::into_parser` transfers the grammar bank into a thread-confined Rust
parser, so workers can retain native state across files without borrowing a
factory's stack frame. The parser frees its native handle before closing the
owned bank; trees and queries continue to borrow the parser. The existing
borrowed constructor and thread restrictions remain in place. Native reuse
controls retain earlier trees and captures across strict refusal, and
compile-fail examples enforce both ownership forms.
