// SPDX-FileCopyrightText: © 2024 Leo Moser <leo.moser@pm.me>
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns/1ps
`default_nettype none

`define SPRITE_WIDTH 12
`define SPRITE_HEIGHT 12

/*
    TODO checklist
    - GL test
    - next_vertical/next_frame at the start
*/

module top (
    input  logic clk_i,
    input  logic rst_ni,

    // SPI signals
    input  logic spi_sclk,
    input  logic spi_mosi,
    output logic spi_miso,
    input  logic spi_cs,

    // SPI Mode
    input  logic spi_mode,

    // SVGA signals
    output logic [5:0] rrggbb,
    output logic hsync,
    output logic vsync,
    output logic next_vertical,
    output logic next_frame
);

    /*
        SVGA Timing for 800x600 60 Hz
        clock = 40 MHz
    */

    localparam WIDTH    = 800;
    localparam HEIGHT   = 600;
    
    localparam HFRONT   = 40;
    localparam HSYNC    = 128;
    localparam HBACK    = 88;

    localparam VFRONT   = 1;
    localparam VSYNC    = 4;
    localparam VBACK    = 23;
    
    localparam HTOTAL = WIDTH + HFRONT + HSYNC + HBACK;
    localparam VTOTAL = HEIGHT + VFRONT + VSYNC + VBACK;
    
    // Downscaling by factor of 8, i.e. one pixel is 8x8
    localparam WIDTH_SMALL  = WIDTH / 8;
    localparam HEIGHT_SMALL = HEIGHT / 8;
    
    /*
        Global Parameters
    */
    
    localparam SPRITE_WIDTH = `SPRITE_WIDTH;
    localparam SPRITE_HEIGHT = `SPRITE_HEIGHT;
    
    localparam bit [5:0] COLOR1_DEFAULT = 6'b110001;
    localparam bit [5:0] COLOR2_DEFAULT = 6'b010101;
    localparam bit [5:0] COLOR3_DEFAULT = 6'b001100;
    localparam bit [5:0] COLOR4_DEFAULT = 6'b101100;
    
    localparam bit [7:0] SPRITE_X_DEFAULT = 0;
    localparam bit [7:0] SPRITE_Y_DEFAULT = 0;
    
    localparam bit [1:0] BACKGROUND_DEFAULT         = 2'd2;
    localparam bit       ENABLE_MOVEMENT_DEFAULT    = 1'b1;
    localparam bit       ENABLE_SPRITE_BG_DEFAULT   = 1'b0;
    
    localparam bit [3:0] MISC_DEFAULT = {   ENABLE_SPRITE_BG_DEFAULT,
                                            ENABLE_MOVEMENT_DEFAULT,
                                            BACKGROUND_DEFAULT
                                        };

    /*
        Horizontal and Vertical Timing
    */
    
    logic signed [$clog2(HTOTAL) : 0] counter_h;
    logic signed [$clog2(VTOTAL) : 0] counter_v;
    
    logic hblank;
    logic vblank;
     
    // Horizontal timing
    timing #(
        .RESOLUTION     (WIDTH),
        .FRONT_PORCH    (HFRONT),
        .SYNC_PULSE     (HSYNC),
        .BACK_PORCH     (HBACK),
        .TOTAL          (HTOTAL),
        .POLARITY       (1)
    ) timing_hor (
        .clk        (clk_i),
        .enable     (1'b1),
        .reset_n    (rst_ni),
        .sync       (hsync),
        .blank      (hblank),
        .next       (next_vertical),
        .counter    (counter_h)
    );
    
    // Vertical timing
    timing #(
        .RESOLUTION     (HEIGHT),
        .FRONT_PORCH    (VFRONT),
        .SYNC_PULSE     (VSYNC),
        .BACK_PORCH     (VBACK),
        .TOTAL          (VTOTAL),
        .POLARITY       (1)
    ) timing_ver (
        .clk        (clk_i),
        .enable     (next_vertical),
        .reset_n    (rst_ni),
        .sync       (vsync),
        .blank      (vblank),
        .next       (next_frame),
        .counter    (counter_v)
    );
    
    logic [7:0] cur_time;
    logic time_dir;

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            cur_time <= '0;
            time_dir <= '0;
        end else begin
            if (next_frame) begin
                if (time_dir == 1'b0) begin
                    cur_time <= cur_time + 1;
                    if (cur_time == 255-1) begin
                        time_dir <= 1'b1;
                    end
                end else begin
                    cur_time <= cur_time - 1;
                    if (cur_time == 0+1) begin
                        time_dir <= 1'b0;
                    end
                end
            end
        end
    end
    
    // Synchronizer to prevent metastability
    logic spi_mosi_sync;
    synchronizer  #(
        .FF_COUNT(2)
    ) synchronizer_spi_mosi (
        .clk        (clk_i),
        .reset_n    (rst_ni),
        .in         (spi_mosi),
        .out        (spi_mosi_sync)
    );

    logic spi_cs_sync;
    synchronizer  #(
        .FF_COUNT(2)
    ) synchronizer_spi_cs (
        .clk        (clk_i),
        .reset_n    (rst_ni),
        .in         (spi_cs),
        .out        (spi_cs_sync)
    );

    logic spi_sclk_sync;
    synchronizer  #(
        .FF_COUNT(2)
    ) synchronizer_spi_sclk (
        .clk        (clk_i),
        .reset_n    (rst_ni),
        .in         (spi_sclk),
        .out        (spi_sclk_sync)
    );
    

    /*
        SPI Receiver
        
        cpol       = False,
        cpha       = True,
        msb_first  = True,
        word_width = 8,
        cs_active_low = True
    */
    
    logic [5:0] color1;
    logic [5:0] color2;
    logic [5:0] color3;
    logic [5:0] color4;
    logic [7:0] sprite_x_reg;
    logic [7:0] sprite_y_reg;
    logic [4:0] misc;
    
    spi_receiver #(
        .COLOR1_DEFAULT (COLOR1_DEFAULT),
        .COLOR2_DEFAULT (COLOR2_DEFAULT),
        .COLOR3_DEFAULT (COLOR3_DEFAULT),
        .COLOR4_DEFAULT (COLOR4_DEFAULT),
        .SPRITE_X_DEFAULT (SPRITE_X_DEFAULT),
        .SPRITE_Y_DEFAULT (SPRITE_Y_DEFAULT),
        .MISC_DEFAULT   (MISC_DEFAULT)
    ) spi_receiver_inst (
        .clk_i      (clk_i), 
        .rst_ni     (rst_ni),

        .enable     (spi_mode == 1'b0),

        .spi_sclk   (spi_sclk_sync),
        .spi_mosi   (spi_mosi_sync),
        .spi_miso   (spi_miso),
        .spi_cs     (spi_cs_sync),

        .color1     (color1),
        .color2     (color2),
        .color3     (color3),
        .color4     (color4),
        .sprite_x   (sprite_x_reg),
        .sprite_y   (sprite_y_reg),
        .misc       (misc)
    );

    /*
        Sprite Movement
    */
    
    logic [7:0] sprite_x_mov;
    logic [7:0] sprite_y_mov;
    
    sprite_movement #(
        .SPRITE_WIDTH  (SPRITE_WIDTH),
        .SPRITE_HEIGHT (SPRITE_HEIGHT),
        .WIDTH_SMALL   (WIDTH_SMALL),
        .HEIGHT_SMALL  (HEIGHT_SMALL)
    ) sprite_movement_inst (
        .clk            (clk_i),
        .reset_n        (rst_ni),
        
        .enable_movement (misc[2]),
        .next_frame     (next_frame),
        
        .sprite_x       (sprite_x_mov),
        .sprite_y       (sprite_y_mov)
    );
    
    logic [7:0] new_sprite_x;
    logic [7:0] new_sprite_y;
    
    assign new_sprite_x = misc[2] ? sprite_x_mov : sprite_x_reg;
    assign new_sprite_y = misc[2] ? sprite_y_mov : sprite_y_reg;
    
    logic [7:0] sprite_x;
    logic [7:0] sprite_y;

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            sprite_x <= '0;
            sprite_y <= '0;
        end else begin
            if (next_vertical) begin
                sprite_x <= new_sprite_x > (WIDTH_SMALL - SPRITE_WIDTH) ? WIDTH_SMALL - SPRITE_WIDTH : new_sprite_x;
                sprite_y <= new_sprite_y > (HEIGHT_SMALL - SPRITE_HEIGHT) ? HEIGHT_SMALL - SPRITE_HEIGHT : new_sprite_y;
            end
        end
    end
    
    logic signed [$clog2(HTOTAL) - 3 : 0] counter_h_small;
    logic signed [$clog2(VTOTAL) - 3 : 0] counter_v_small;

    assign counter_h_small = counter_h[$clog2(HTOTAL) : 3];
    assign counter_v_small = counter_v[$clog2(VTOTAL) : 3];

    /*
        Sprite Visibility
    */

    logic sprite_visible_v;
    logic sprite_visible_h;
    logic sprite_visible;
    
    assign sprite_visible_h = counter_h_small >= {1'b0, sprite_x} && counter_h_small < (sprite_x + SPRITE_WIDTH);
    assign sprite_visible_v = counter_v_small >= sprite_y && counter_v_small < (sprite_y + SPRITE_HEIGHT);
    assign sprite_visible = sprite_visible_h && sprite_visible_v;
    
    /*
        Sprite Data
    */
    
    logic sprite_shift;
    logic sprite_data;
    
    // Detect spi_clk edge
    logic spi_sclk_delayed;
    always_ff @(posedge clk_i) begin
        spi_sclk_delayed <= spi_sclk_sync;
    end
    
    logic spi_sclk_falling, spi_sclk_rising;
    assign spi_sclk_rising = !spi_sclk_delayed && spi_sclk_sync;
    assign spi_sclk_falling = spi_sclk_delayed && !spi_sclk_sync;
    
    sprite_data #(
        .WIDTH  (SPRITE_WIDTH),
        .HEIGHT (SPRITE_HEIGHT)
    ) sprite_data_inst (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .shiftf     (sprite_shift || (spi_mode == 1'b1 && !spi_cs_sync && spi_sclk_falling)),
        .data_out   (sprite_data),
        .data_in    (spi_mosi_sync),
        .load       (spi_mode == 1'b1)
    );
    
    /*
        Sprite Access
    */
    
    logic sprite_pixel;
    logic start_big_line;
    logic end_big_pixel;
    
    assign start_big_line = counter_v[2:0] == 3'b000;
    assign end_big_pixel   = counter_h[2:0] == 3'b111;
    
    sprite_access #(
        .WIDTH  (SPRITE_WIDTH)
    ) sprite_access_inst (
        .clk            (clk_i),

        .new_line       (start_big_line),
        .sprite_access  (end_big_pixel),
        
        .sprite_data    (sprite_data),
        .sprite_shift   (sprite_shift),

        .sprite_pixel   (sprite_pixel),
        .sprite_visible (sprite_visible)
    );
    
    /*
        Background Color
    */
    
    logic [5:0] bg_color;
    
    logic [1:0] bg_sel;

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            bg_sel <= BACKGROUND_DEFAULT;
        end else begin
            // Only ever assign at next_frame
            // to prevent glitches
            if (next_vertical && counter_v[2:0] == 3'b111) begin
                bg_sel <= misc[1:0];
            end
        end
    end
    
    background #(
        .HTOTAL (HTOTAL),
        .VTOTAL (VTOTAL)
    ) background_inst (
        .bg_select  (bg_sel),
        .cur_time   (cur_time),

        .counter_h  (counter_h),
        .counter_v  (counter_v),

        .color1     (color1),
        .color2     (color2),
        .color3     (color3),
        .color4     (color4),
        
        .color_out (bg_color)
    );
    
    /*
        Final Color Composition
    */

    always_comb begin
        rrggbb = bg_color;
        
        if (sprite_pixel && sprite_visible) begin
            rrggbb = color1;
        end
        
        if (misc[3] && !sprite_pixel && sprite_visible) begin
            rrggbb = color2;
        end
        
        if (hblank || vblank) begin
            rrggbb = '0;
        end
    end


endmodule
