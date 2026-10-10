// Basys 3 wrapper: 100 MHz board clock -> 25 MHz CPU clock, a0 shown on LEDs.
// (Simple divided clock through a BUFG is fine for learning; for a real design
//  use a Clocking Wizard / MMCM or a clock-enable instead.)
module fpga_top (
    input         clk100,     // W5
    input         btnC,       // U18, centre button = reset
    output [15:0] led
);
    reg [1:0] div = 2'b00;
    always @(posedge clk100) div <= div + 1'b1;

    wire cpu_clk;
    BUFG u_bufg (.I(div[1]), .O(cpu_clk));        // 100 MHz / 4 = 25 MHz

    // reset synchroniser
    reg [1:0] rst_sync = 2'b11;
    always @(posedge cpu_clk) rst_sync <= {rst_sync[0], btnC};

    wire [31:0] pc, a0;
    riscv_pipeline #(.IMEM_FILE("blink.hex")) cpu (
        .clk(cpu_clk), .rst(rst_sync[1]), .dbg_pc(pc), .dbg_a0(a0)
    );

    assign led = a0[15:0];
endmodule
