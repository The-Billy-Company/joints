module m;
	wire [15:0] w;
	assign w = {mem_rdata_latched[12:11], mem_rdata_latched[5], 2'b00};
endmodule
