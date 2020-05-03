module imx219 #(
    parameter int INPUT_CLK_RATE,
    parameter int TARGET_SCL_RATE = 400000,
    // Some IMX219 modules have a different address, change this if yours does
    parameter bit [7:0] ADDRESS = 8'h20
) (
    input logic clk_in,
    inout wire scl,
    inout wire sda,
    // 0 = Power off
    // 1 = Software standby
    // 2 = Streaming
    input logic [1:0] mode,

    // 0 = 3280x2464
    // 1 = 1920x1080
    // 2 = 1640x1232
    // 3 = 640x480
    input logic [1:0] resolution,
    // 0 = RAW8
    // 1 = RAW10
    input logic format,
    // input logic horizontal_flip,
    // input logic vertical_flip,
    // input logic [7:0] analog_gain,
    // input logic [15:0] digital_gain,
    // input logic [15:0] exposure, // aka integration time

    // Goes high when inputs match sensor state
    // Changing inputs when the sensor isn't ready could put the sensor into an unexpected state
    output logic ready,
    output logic power_enable,
    // IMX219 Model ID did not match
    output logic model_err = 1'b0,
    output logic nack_err = 1'b0
);

logic bus_clear;

logic transfer_start = 1'b0;
logic transfer_continues = 1'b0;
logic [7:0] address;
logic [7:0] data_tx = 8'd0;

logic transfer_ready;
logic interrupt;
logic transaction_complete;
logic nack;
logic [7:0] data_rx;
logic address_err;

i2c_master #(.INPUT_CLK_RATE(INPUT_CLK_RATE), .TARGET_SCL_RATE(TARGET_SCL_RATE)) i2c_master (
    .scl(scl),
    .clk_in(clk_in),
    .bus_clear(bus_clear),
    .sda(sda),
    .address(address),
    .transfer_start(transfer_start),
    .transfer_continues(transfer_continues),
    .data_tx(data_tx),
    .transfer_ready(transfer_ready),
    .interrupt(interrupt),
    .transaction_complete(transaction_complete),
    .nack(nack),
    .data_rx(data_rx),
    .address_err(address_err)
);

logic [15:0] MODEL_ID = 16'h0219;

logic [24:0] PRE_STANDBY [0:2];
assign PRE_STANDBY = '{
    {1'b1, 16'h0000, MODEL_ID[15:8]},   // Read module_model_id high
	{1'b1, 16'h0001, MODEL_ID[7:0]},    // Read module_model_id low
	// {1'b0, 16'h0100, 8'd1},				// mode_select <= streaming (forces LP-11 on standby) 
    {1'b0, 16'h0100, 8'd0}              // mode_select <= standby
};

logic [24:0] PRE_STREAM [0:58];
assign PRE_STREAM = '{
	{1'b0, 16'h30eb, 8'h05}, // Manufacturer access command sequence (See Section 3-4)
	{1'b0, 16'h30eb, 8'h0c},
	{1'b0, 16'h300a, 8'hff},
	{1'b0, 16'h300b, 8'hff},
	{1'b0, 16'h30eb, 8'h05},
	{1'b0, 16'h30eb, 8'h09},
	{1'b0, 16'h0114, 8'h01}, // CSI Lane Count (2)
	{1'b0, 16'h0128, 8'h00}, // MIPI Global timing (auto)
	{1'b0, 16'h012a, 8'h18}, // External Clock Frequency MSB (24MHz)
	{1'b0, 16'h012b, 8'h00}, // External Clock Frequency LSB
	{1'b0, 16'h0160, resolution == 2'd0 ? 8'h0d : 8'h06}, // Frame length MSB (15 FPS for full-frame, 30 FPS for other resolutions)
	{1'b0, 16'h0161, resolution == 2'd0 ? 8'hc6 : 8'he3}, // Frame length LSB
	{1'b0, 16'h0162, 8'h0d}, // Pixel clocks per line MSB (3448)
	{1'b0, 16'h0163, 8'h78}, // Pixel clocks per line LSB
	{1'b0, 16'h0164, resolution == 2'd0 ? 8'h00 : resolution == 2'd1 ? 8'h02 : resolution == 2'd2 ? 8'h00: 8'h03}, // X-address start MSB
	{1'b0, 16'h0165, resolution == 2'd0 ? 8'h00 : resolution == 2'd1 ? 8'ha8 : resolution == 2'd2 ? 8'h00: 8'he8}, // X-address start LSB
	{1'b0, 16'h0166, resolution == 2'd0 ? 8'h0c : resolution == 2'd1 ? 8'h08 : resolution == 2'd2 ? 8'h0c: 8'h08}, // X-address end MSB
	{1'b0, 16'h0167, resolution == 2'd0 ? 8'hcf : resolution == 2'd1 ? 8'h27 : resolution == 2'd2 ? 8'hcf: 8'he7}, // X-address end LSB
	{1'b0, 16'h0168, resolution == 2'd0 ? 8'h00 : resolution == 2'd1 ? 8'h02 : resolution == 2'd2 ? 8'h00: 8'h02}, // Y-address start MSB
	{1'b0, 16'h0169, resolution == 2'd0 ? 8'h00 : resolution == 2'd1 ? 8'hb4 : resolution == 2'd2 ? 8'h00: 8'hf0}, // Y-address start LSB
	{1'b0, 16'h016a, resolution == 2'd0 ? 8'h09 : resolution == 2'd1 ? 8'h06 : resolution == 2'd2 ? 8'h09: 8'h06}, // Y-address end MSB
	{1'b0, 16'h016b, resolution == 2'd0 ? 8'h9f : resolution == 2'd1 ? 8'heb : resolution == 2'd2 ? 8'h9f: 8'haf}, // Y-address end LSB

	{1'b0, 16'h016c, resolution == 2'd0 ? 8'h0c : resolution == 2'd1 ? 8'h07 : resolution == 2'd2 ? 8'h06 : 8'h02}, // X-output size MSB
	{1'b0, 16'h016d, resolution == 2'd0 ? 8'hd0 : resolution == 2'd1 ? 8'h80 : resolution == 2'd2 ? 8'h68 : 8'h80}, // X-output size LSB
	{1'b0, 16'h016e, resolution == 2'd0 ? 8'h09 : resolution == 2'd1 ? 8'h04 : resolution == 2'd2 ? 8'h04 : 8'h01}, // Y-output size MSB
	{1'b0, 16'h016f, resolution == 2'd0 ? 8'ha0 : resolution == 2'd1 ? 8'h38 : resolution == 2'd2 ? 8'hd0 : 8'he0}, // Y-output size LSB
	{1'b0, 16'h0170, 8'h01}, // X odd increment
	{1'b0, 16'h0171, 8'h01}, // Y odd increment
	{1'b0, 16'h0174, resolution == 2'd0 ? 8'h00 : resolution == 2'd1 ? 8'h00 : resolution == 2'd2 ? 8'h01 : 8'h03}, // Vertical binning mode
	{1'b0, 16'h0175, resolution == 2'd0 ? 8'h00 : resolution == 2'd1 ? 8'h00 : resolution == 2'd2 ? 8'h01 : 8'h03}, // Horizontal binning mode
	{1'b0, 16'h018c, format ? 8'h0a : 8'h08}, // CSI data format MSB
	{1'b0, 16'h018d, format ? 8'h0a : 8'h08}, // CSI data format LSB
	{1'b0, 16'h0301, format ? 8'h05 : 8'h04}, // Video timing pixel clock divider (/5 for 10-bit, /4 for 8-bit)
	{1'b0, 16'h0303, 8'h01}, // Video timing system clock divider (always /1)
	{1'b0, 16'h0304, 8'h03}, // External (pre-PLL) clock divider for video timing (3 for 24MHz to 27MHz)
	{1'b0, 16'h0305, 8'h03}, // External (pre-PLL) clock divider for output (3 for 24MHz to 27MHz)
	{1'b0, 16'h0306, 8'h00}, // PLL video timing system multiplier MSB
	{1'b0, 16'h0307, 8'h20}, // PLL video timing system multiplier LSB
	{1'b0, 16'h0309, format ? 8'h0a : 8'h08}, // Output pixel clock divider (/10 for 10-bit, /8 for 8-bit)
	{1'b0, 16'h030b, 8'h01}, // Output sytem clock divider (always /2)
	{1'b0, 16'h030c, 8'h00}, // PLL output system clock multiplier MSB
	{1'b0, 16'h030d, 8'h40}, // PLL output system clock multiplier LSB (DDR clock, as compared to 0x0307)
	{1'b0, 16'h0624, resolution == 2'd0 ? 8'h0c : resolution == 2'd1 ? 8'h07 : resolution == 2'd2 ? 8'h06 : 8'h02}, // Test pattern window width MSB
	{1'b0, 16'h0625, resolution == 2'd0 ? 8'hd0 : resolution == 2'd1 ? 8'h80 : resolution == 2'd2 ? 8'h68 : 8'h80}, // Test pattern window width LSB
	{1'b0, 16'h0626, resolution == 2'd0 ? 8'h09 : resolution == 2'd1 ? 8'h04 : resolution == 2'd2 ? 8'h04 : 8'h01}, // Test pattern window height MSB
	{1'b0, 16'h0627, resolution == 2'd0 ? 8'ha0 : resolution == 2'd1 ? 8'h38 : resolution == 2'd2 ? 8'hd0 : 8'he0}, // Test pattern window height LSB
	{1'b0, 16'h455e, 8'h00}, // CMOS Image Sensor Tuning for all below
	{1'b0, 16'h471e, 8'h4b},
	{1'b0, 16'h4767, 8'h0f},
	{1'b0, 16'h4750, 8'h14},
	{1'b0, 16'h4540, 8'h00},
	{1'b0, 16'h47b4, 8'h14},
	{1'b0, 16'h4713, 8'h30},
	{1'b0, 16'h478b, 8'h10},
	{1'b0, 16'h478f, 8'h10},
	{1'b0, 16'h4793, 8'h10},
	{1'b0, 16'h4797, 8'h0e},
	{1'b0, 16'h479b, 8'h0e},
	{1'b0, 16'h0100, 8'h01} // Start streaming
};

logic [24:0] POST_STREAM [0:0];
assign POST_STREAM = '{
	{1'b0, 16'h0100, 8'h00} // Send to standby
	// TODO: standby spinlock
};


// 0 = Off
// 1 = Pre-Standby
// 2 = Standby
// 3 = Pre-Stream
// 4 = Stream
// 5 = Modify Stream
// 6 = Post Stream (shutting down)
// 7 = Error
logic [2:0] sensor_state = 3'd0;

logic [7:0] rom_counter = 8'd0;
logic [1:0] byte_counter = 2'd0;

// Uninit, Standby, or Stream
assign ready = sensor_state == 3'd0 || sensor_state == 3'd2 || sensor_state == 3'd4;

assign power_enable = sensor_state != 3'd0;

logic [7:0] rom_end;
assign rom_end = sensor_state == 3'd1 ? 8'd2 : sensor_state == 3'd3 ? 8'd58 : sensor_state == 3'd6 ? 8'd0 : 8'd0;

logic [24:0] current_rom;
assign current_rom = sensor_state == 3'd1 ? PRE_STANDBY[rom_counter] : sensor_state == 3'd3 ? PRE_STREAM[rom_counter] : sensor_state == 3'd6 ? POST_STREAM[rom_counter] : 25'd0;

always @(posedge clk_in)
begin
    case (sensor_state)
        3'd0: begin 
			if (mode != 2'd0)
				sensor_state <= 3'd1;
        end
        3'd1, 3'd3, 3'd6: begin
			if (interrupt || transfer_ready)
			begin
				if (interrupt && (address_err || (!address[0] && nack))) // Catch write nacks
				begin
					transfer_start <= 1'b0;
					transfer_continues <= 1'b0;
					byte_counter <= 2'd0;
					rom_counter <= 8'd0;
					nack_err <= 1'd1;
					sensor_state <= 3'd7;
				end
				else if (transfer_ready && byte_counter == 2'd0) // Write address MSB
				begin
					transfer_start <= 1'd1;
					transfer_continues <= 1'd1;
					address <= {ADDRESS[7:1], 1'b0};
					data_tx <= current_rom[23:16];
					byte_counter <= 2'd1;
				end
				else if (interrupt && byte_counter == 2'd1) // Write address LSB
				begin
					transfer_start <= 1'd0;
					transfer_continues <= !current_rom[24];
					data_tx <= current_rom[15:8];
					byte_counter <= 2'd2;
				end
				else if (interrupt && byte_counter == 2'd2) // Write/Read register
				begin
					transfer_start <= current_rom[24];
					transfer_continues <= 1'd0;
					if (current_rom[24])
						address <= {ADDRESS[7:1], 1'b1};
					data_tx <= current_rom[7:0];
					byte_counter <= 2'd3;
				end
				else if (interrupt && byte_counter == 2'd3) // Readback
				begin
					transfer_start <= 1'd0;
					transfer_continues <= 1'd0;
					byte_counter <= 2'd0;

					if (current_rom[24] && current_rom[7:0] != data_rx) // Read did not match expected
					begin
						rom_counter <= 8'd0;
						if (sensor_state == 3'd1) // was a model error
							model_err <= 1'd1;
						sensor_state <= 3'd7;
					end
					else if (rom_counter == rom_end) // This was the last operation
					begin
						rom_counter <= 8'd0;
						if (sensor_state == 3'd5)
							sensor_state <= 3'd4; // Modifications complete
						else if (sensor_state == 3'd6)
							sensor_state <= mode == 2'd1 ? 3'd2 : 3'd0; // Either go to standby or power off
						else
							sensor_state <= sensor_state + 1'd1; // Pre-standby and Pre-stream
					end
					else
						rom_counter <= rom_counter + 1'd1;
				end
			end
        end
        3'd2: begin
            if (mode == 2'd0)
                sensor_state <= 3'd0;
            else if (mode == 2'd2)
                sensor_state <= 3'd3;
            else
                sensor_state <= 3'd2;
        end
		3'd4: begin
			if (mode != 2'd2)
				sensor_state <= 3'd6;
			else
				sensor_state <= 3'd4;
		end
		3'd5: begin // Not entered, modify support still WIP
		end
        3'd7: begin
            if (mode == 2'd0)
            begin
                model_err <= 1'd0;
                nack_err <= 1'd0;
                sensor_state <= 3'd0;
            end
        end
    endcase
end

endmodule
