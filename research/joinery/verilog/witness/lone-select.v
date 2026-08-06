// The wall, in 56 bytes. A concatenation element that is exactly one selected
// identifier and nothing else. Refused today at the `;`, in state 701.
//
// Not a preprocessor question and not an external scanner question - verilog
// declares zero externals. State 701 is `casting_type -> constant_primary .`
// and accepts one terminal in all of verilog, so nothing can be repaired there;
// by then the parse is inside a cast's operand and it is already over.
//
// It got there at the `]`. Under OUTLINER_TRACE=quire the whole parse is three
// lines, and the second is the defect: state 2979 keeps `constant_primary` and
// casts off `primary` - the reading a concatenation needs - with rank 0 on both
// sides, so nothing in the grammar breaks that tie and the tie is broken anyway.
// `grammar.json` declares ['primary', 'variable_lvalue'] outright.
module m; reg [31:0] a, c; assign c = {a[3]}; endmodule
