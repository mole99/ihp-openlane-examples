module counter (
    input clk_i,
    input rst_ni,
    output [7:0] out_o
);

logic [7:0] count;

always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
        count <= '0;
    end else begin
        count <= count + 1;
    end
end

assign out_o = count;

endmodule
