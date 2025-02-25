// SPDX-FileCopyrightText: © 2024 Leo Moser <leo.moser@pm.me>
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns/1ps
`default_nettype none

module spi_receiver #(
    parameter NUM_REGISTERS = 7,
    parameter LEN_REGISTER = 8,

    parameter COLOR1_DEFAULT,   // color1 default value
    parameter COLOR2_DEFAULT,   // color2 default value
    parameter COLOR3_DEFAULT,   // color3 default value
    parameter COLOR4_DEFAULT,   // color4 default value
    
    parameter SPRITE_X_DEFAULT, // sprite x default value
    parameter SPRITE_Y_DEFAULT, // sprite y default value
    
    parameter MISC_DEFAULT      // misc default value
)(
    input  logic clk_i,         // clock
    input  logic rst_ni,        // reset active low
    
    input  logic enable,        // enable SPI receiver
    
    // SPI signals
    input  logic spi_sclk,
    input  logic spi_mosi,
    output logic spi_miso,
    input  logic spi_cs,

    // Output register
    output logic [5:0] color1,      // color1 register
    output logic [5:0] color2,      // color2 register
    output logic [5:0] color3,      // color3 register
    output logic [5:0] color4,      // color4 register
    output logic [7:0] sprite_x,    // sprite x register
    output logic [7:0] sprite_y,    // sprite y register
    output logic [4:0] misc         // miscellaneous register
);
    // Detect spi_clk edge
    logic spi_sclk_delayed;
    always_ff @(posedge clk_i) begin
        spi_sclk_delayed <= spi_sclk;
    end
    
    logic spi_sclk_falling, spi_sclk_rising;
    assign spi_sclk_rising = !spi_sclk_delayed && spi_sclk;
    assign spi_sclk_falling = spi_sclk_delayed && !spi_sclk;
    
    // State Machine

    // Active SPI command
    // #bits depend on number of registers
    logic [$clog2(NUM_REGISTERS)-1:0] spi_cmd;

    // SPI data
    logic [LEN_REGISTER-1:0] spi_data;
    
    // Count up to 8 bits
    logic [2:0] spi_cnt;
    
    // 0 = cmd, 1 = data
    logic spi_mode;
    
    logic load_register;
    
    logic [NUM_REGISTERS-1:0] reg_enable;
    logic [NUM_REGISTERS-1:0] reg_gclk;
    
    logic [LEN_REGISTER-1:0] registers [NUM_REGISTERS];
    
    logic [LEN_REGISTER-1:0] defaults [NUM_REGISTERS];
    
    assign defaults[0] = COLOR1_DEFAULT;
    assign defaults[1] = COLOR2_DEFAULT;
    assign defaults[2] = COLOR3_DEFAULT;
    assign defaults[3] = COLOR4_DEFAULT;
    assign defaults[4] = SPRITE_X_DEFAULT;
    assign defaults[5] = SPRITE_Y_DEFAULT;
    assign defaults[6] = MISC_DEFAULT;
    
    generate
    
    for (genvar i=0; i<NUM_REGISTERS; i++) begin : regs
        assign reg_enable[i] = spi_cmd == i;
        
        // Clock gating
        sg13g2_lgcp_1 sg13g2_lgcp_1_inst (
            .GCLK   (reg_gclk[i]),
            .GATE   (reg_enable[i] && load_register),
            .CLK    (clk_i)
        );
        
        // FF
        /*always_ff @(posedge reg_gclk[i], negedge rst_ni) begin
            if (!rst_ni) begin
                registers[i] <= defaults[i];
            end else begin
                registers[i] <= spi_data;
            end
        end*/
        
        // Latches
        always_latch begin
            if (!rst_ni) begin
                registers[i] <= defaults[i];
            end else if (reg_gclk[i]) begin
                registers[i] <= spi_data;
            end
        end

        /*always @*
        if (rst_ni == 1'b0)
                registers[i] <= defaults[i];
        else if (reg_gclk[i] == 1'b1)
                registers[i] <= spi_data;*/
    end
    
    endgenerate
    
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            spi_cmd <= '0;
            spi_data <= '0;
            spi_mode <= 1'b0;
            spi_cnt  <= '0;
            
            load_register <= 1'b0;
        end else begin
            load_register <= 1'b0;
        
            // TODO enable?
            if (!spi_cs && spi_sclk_falling && enable) begin
                // Read the command
                if (spi_mode == 1'b0) begin
                    spi_cmd <= {spi_cmd[1:0], spi_mosi};
                    spi_cnt <= spi_cnt + 1;
                    
                    if (spi_cnt == 7) begin
                        spi_mode <= 1'b1;
                    end
                // Read the data
                end else begin
                    spi_data <= {spi_data[LEN_REGISTER-2:0], spi_mosi};
                    spi_cnt <= spi_cnt + 1;

                    if (spi_cnt == 7) begin
                        spi_mode <= 1'b0;
                        load_register <= 1'b1;
                    end
                end
            end
        end
    end
    
    assign spi_miso = 1'b0;
    
    // Assign registers
    assign color1 = registers[0];
    assign color2 = registers[1];
    assign color3 = registers[2];
    assign color4 = registers[3];
    assign sprite_x = registers[4];
    assign sprite_y = registers[5];
    assign misc = registers[6];
    
endmodule
