// The same file with one pair of parentheses, accepted. Its whole job is to be
// the arm that says the sibling's refusal is about this construct and not about
// `assign`, `reg`, a range, a brace, or the size of the file.
//
// `{a[3]+1}`, `{!a[3]}`, `{(a[3])}` and `{a}` are all accepted too, so the wall
// is not "a select inside braces" - it is a select that is the *whole* element,
// where the fold is asked for on `}` or `,` rather than on an operator.
module m; reg [31:0] a, c; assign c = {(a[3])}; endmodule
