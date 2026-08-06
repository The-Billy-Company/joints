module picorv32 (
	input             clk,
	input      [31:0] irq,
	output reg [31:0] eoi,

`ifdef RISCV_FORMAL
	output reg        rvfi_valid,
	output reg [63:0] rvfi_order,
`endif

	output reg        trace_valid
);
endmodule
