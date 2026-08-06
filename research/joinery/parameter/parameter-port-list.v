module a (
	input clk,
`ifdef RISCV_FORMAL
	output reg v,
`endif
	output q
);
endmodule

module b #(
	parameter [ 0:0] P0 = 1,
	parameter [31:0] P1 = 32'h 0000_0000
) (
	input clk
);
endmodule
