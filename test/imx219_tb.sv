module imx219_tb();

// Initially, lines are grounded
logic clock_p = 0;
logic clock_n = 0;
always
begin
    #2ns;
    clock_p <= ~clock_p;
    clock_n <= clock_p;
end

logic [1:0] data_p = 2'd0;
logic [1:0] data_n;
assign data_n = ~data_p;

logic clk_in;
wire scl;
wire sda;
logic [1:0] mode;
logic [1:0] resolution;
logic format;
logic ready;
logic power_enable;
logic model_err;
logic nack_err;

imx219 #(.INPUT_CLK_RATE(48000000)) imx219 (
    .clk_in(clk_in),
    .scl(scl),
    .sda(sda),
    // 0 = Power off
    // 1 = Software standby
    // 2 = Streaming
    .mode(mode),

    // 0 = 3280x2464
    // 1 = 1920x1080
    // 2 = 1640x1232
    // 3 = 640x480
    .resolution(resolution),
    // 0 = RAW8
    // 1 = RAW10
    .format(format),

    // Goes high when inputs match sensor state
    // Changing inputs when the sensor isn't ready could put the sensor into an unexpected state
    .ready(ready),
    .power_enable(power_enable),
    // IMX219 Model ID did not match
    .model_err(model_err),
    .nack_err(nack_err)
);

initial
begin
    $finish;
end

endmodule
