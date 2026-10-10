// =====================================================================
//  RV32I 5-stage pipelined CPU   (IF - ID - EX - MEM - WB)
//  - Data forwarding  : EX/MEM -> EX and MEM/WB -> EX
//  - Load-use hazard  : 1-cycle stall
//  - Branches / jumps : resolved in EX, 2-cycle flush penalty when taken
//  - Harvard memories : separate instruction and data memory
//  Not implemented: CSRs, ECALL/EBREAK/FENCE (treated as NOP), exceptions
// =====================================================================
module riscv_pipeline #(
    parameter IMEM_FILE = "program.hex"
)(
    input         clk,
    input         rst,           // synchronous, active high
    output [31:0] dbg_pc,
    output [31:0] dbg_a0,        // register x10 (a0), handy for LEDs
    output        dbg_retire     // 1 when a real (non-bubble) instruction completes
);
    localparam NOP = 32'h00000013;

    // ALU operation codes (must match alu.v)
    localparam ALU_ADD=4'd0, ALU_SUB=4'd1, ALU_SLL=4'd2, ALU_SLT=4'd3, ALU_SLTU=4'd4,
               ALU_XOR=4'd5, ALU_SRL=4'd6, ALU_SRA=4'd7, ALU_OR=4'd8,  ALU_AND=4'd9;

    // Opcodes
    localparam OP_R=7'b0110011, OP_I=7'b0010011, OP_LOAD=7'b0000011, OP_STORE=7'b0100011,
               OP_BR=7'b1100011, OP_JAL=7'b1101111, OP_JALR=7'b1100111,
               OP_LUI=7'b0110111, OP_AUIPC=7'b0010111;

    // ----------------------------------------------------------------
    // Pipeline-wide wires
    // ----------------------------------------------------------------
    wire        stall;            // load-use hazard: freeze IF/ID, bubble ID/EX
    wire        take_branch;      // branch/jump resolved in EX
    wire [31:0] branch_target;
    wire [31:0] wb_data;          // value written back in WB stage

    // =================================================================
    // IF stage
    // =================================================================
    reg  [31:0] pc;
    wire [31:0] instr_f;
    wire [31:0] pc_plus4 = pc + 32'd4;

    imem #(.FILE(IMEM_FILE)) u_imem (.addr(pc), .instr(instr_f));

    always @(posedge clk) begin
        if (rst)              pc <= 32'd0;
        else if (take_branch) pc <= branch_target;
        else if (!stall)      pc <= pc_plus4;
    end

    // IF/ID register
    reg [31:0] ifid_pc, ifid_instr;
    reg        ifid_valid;           // 0 = bubble (for performance counting only)
    always @(posedge clk) begin
        if (rst || take_branch) begin
            ifid_pc    <= 32'd0;
            ifid_instr <= NOP;
            ifid_valid <= 1'b0;
        end else if (!stall) begin
            ifid_pc    <= pc;
            ifid_instr <= instr_f;
            ifid_valid <= 1'b1;
        end
    end

    // =================================================================
    // ID stage
    // =================================================================
    wire [6:0] opcode = ifid_instr[6:0];
    wire [4:0] id_rd  = ifid_instr[11:7];
    wire [2:0] funct3 = ifid_instr[14:12];
    wire [4:0] id_rs1 = ifid_instr[19:15];
    wire [4:0] id_rs2 = ifid_instr[24:20];
    wire       f7_5   = ifid_instr[30];

    // ---- immediate generator ----
    reg [31:0] id_imm;
    always @* begin
        case (opcode)
            OP_I, OP_LOAD, OP_JALR:
                id_imm = {{20{ifid_instr[31]}}, ifid_instr[31:20]};
            OP_STORE:
                id_imm = {{20{ifid_instr[31]}}, ifid_instr[31:25], ifid_instr[11:7]};
            OP_BR:
                id_imm = {{19{ifid_instr[31]}}, ifid_instr[31], ifid_instr[7],
                          ifid_instr[30:25], ifid_instr[11:8], 1'b0};
            OP_LUI, OP_AUIPC:
                id_imm = {ifid_instr[31:12], 12'b0};
            OP_JAL:
                id_imm = {{11{ifid_instr[31]}}, ifid_instr[31], ifid_instr[19:12],
                          ifid_instr[20], ifid_instr[30:21], 1'b0};
            default: id_imm = 32'd0;
        endcase
    end

    // ---- control unit ----
    reg       c_reg_write, c_mem_read, c_mem_write, c_mem_to_reg;
    reg       c_src_b_imm, c_branch, c_jal, c_jalr;
    reg [1:0] c_src_a;             // 0 = rs1, 1 = pc, 2 = zero
    reg [3:0] c_alu;
    reg [3:0] alu_from_funct;      // ALU op derived from funct3 (R / I type)

    always @* begin
        // funct3 -> ALU op. For I-type, only shifts look at bit 30 (SRAI).
        case (funct3)
            3'b000: alu_from_funct = (opcode == OP_R && f7_5) ? ALU_SUB : ALU_ADD;
            3'b001: alu_from_funct = ALU_SLL;
            3'b010: alu_from_funct = ALU_SLT;
            3'b011: alu_from_funct = ALU_SLTU;
            3'b100: alu_from_funct = ALU_XOR;
            3'b101: alu_from_funct = f7_5 ? ALU_SRA : ALU_SRL;
            3'b110: alu_from_funct = ALU_OR;
            default: alu_from_funct = ALU_AND;
        endcase

        c_reg_write = 0; c_mem_read = 0; c_mem_write = 0; c_mem_to_reg = 0;
        c_src_b_imm = 0; c_branch = 0; c_jal = 0; c_jalr = 0;
        c_src_a = 2'd0;  c_alu = ALU_ADD;

        case (opcode)
            OP_R:     begin c_reg_write = 1; c_alu = alu_from_funct; end
            OP_I:     begin c_reg_write = 1; c_src_b_imm = 1; c_alu = alu_from_funct; end
            OP_LOAD:  begin c_reg_write = 1; c_mem_read = 1; c_mem_to_reg = 1; c_src_b_imm = 1; end
            OP_STORE: begin c_mem_write = 1; c_src_b_imm = 1; end
            OP_BR:    begin c_branch = 1; end
            OP_JAL:   begin c_reg_write = 1; c_jal = 1; end
            OP_JALR:  begin c_reg_write = 1; c_jalr = 1; c_src_b_imm = 1; end
            OP_LUI:   begin c_reg_write = 1; c_src_b_imm = 1; c_src_a = 2'd2; end
            OP_AUIPC: begin c_reg_write = 1; c_src_b_imm = 1; c_src_a = 2'd1; end
            default:  ; // FENCE / ECALL / EBREAK / unknown -> NOP
        endcase
    end

    // ---- register file (written by WB stage) ----
    wire [31:0] id_rs1_val, id_rs2_val;
    reg         memwb_reg_write;
    reg  [4:0]  memwb_rd;

    regfile rf (
        .clk(clk), .we(memwb_reg_write),
        .ra1(id_rs1), .ra2(id_rs2),
        .wa(memwb_rd), .wd(wb_data),
        .rd1(id_rs1_val), .rd2(id_rs2_val),
        .dbg_x10(dbg_a0)
    );

    // ---- load-use hazard detection ----
    reg        idex_mem_read;
    reg [4:0]  idex_rd;
    assign stall = idex_mem_read && (idex_rd != 5'd0) &&
                   (idex_rd == id_rs1 || idex_rd == id_rs2);

    // ---- ID/EX register ----
    reg [31:0] idex_pc, idex_rs1_val, idex_rs2_val, idex_imm;
    reg [4:0]  idex_rs1, idex_rs2;
    reg [2:0]  idex_funct3;
    reg [3:0]  idex_alu;
    reg [1:0]  idex_src_a;
    reg        idex_reg_write, idex_mem_write, idex_mem_to_reg;
    reg        idex_src_b_imm, idex_branch, idex_jal, idex_jalr;
    reg        idex_valid;

    always @(posedge clk) begin
        if (rst || stall || take_branch) begin
            // insert a bubble: clear everything that has side effects
            idex_reg_write <= 0; idex_mem_read <= 0; idex_mem_write <= 0;
            idex_mem_to_reg <= 0; idex_branch <= 0; idex_jal <= 0; idex_jalr <= 0;
            idex_rd <= 5'd0;
            idex_valid <= 1'b0;
        end else begin
            idex_valid      <= ifid_valid;
            idex_reg_write  <= c_reg_write;
            idex_mem_read   <= c_mem_read;
            idex_mem_write  <= c_mem_write;
            idex_mem_to_reg <= c_mem_to_reg;
            idex_branch     <= c_branch;
            idex_jal        <= c_jal;
            idex_jalr       <= c_jalr;
            idex_rd         <= id_rd;
        end
        idex_pc        <= ifid_pc;
        idex_rs1_val   <= id_rs1_val;
        idex_rs2_val   <= id_rs2_val;
        idex_imm       <= id_imm;
        idex_rs1       <= id_rs1;
        idex_rs2       <= id_rs2;
        idex_funct3    <= funct3;
        idex_alu       <= c_alu;
        idex_src_a     <= c_src_a;
        idex_src_b_imm <= c_src_b_imm;
    end

    // =================================================================
    // EX stage
    // =================================================================
    // EX/MEM registers declared here because forwarding reads them
    reg [31:0] exmem_result, exmem_store_data;
    reg [4:0]  exmem_rd;
    reg [2:0]  exmem_funct3;
    reg        exmem_reg_write, exmem_mem_read, exmem_mem_write, exmem_mem_to_reg;
    reg        exmem_valid;

    // ---- forwarding unit ----
    reg [1:0] fwd_a, fwd_b;   // 00 = regfile, 01 = from WB, 10 = from MEM
    always @* begin
        fwd_a = 2'b00;
        if (exmem_reg_write && exmem_rd != 5'd0 && exmem_rd == idex_rs1)      fwd_a = 2'b10;
        else if (memwb_reg_write && memwb_rd != 5'd0 && memwb_rd == idex_rs1) fwd_a = 2'b01;

        fwd_b = 2'b00;
        if (exmem_reg_write && exmem_rd != 5'd0 && exmem_rd == idex_rs2)      fwd_b = 2'b10;
        else if (memwb_reg_write && memwb_rd != 5'd0 && memwb_rd == idex_rs2) fwd_b = 2'b01;
    end

    wire [31:0] rs1_fwd = (fwd_a == 2'b10) ? exmem_result :
                          (fwd_a == 2'b01) ? wb_data      : idex_rs1_val;
    wire [31:0] rs2_fwd = (fwd_b == 2'b10) ? exmem_result :
                          (fwd_b == 2'b01) ? wb_data      : idex_rs2_val;

    // ---- ALU ----
    wire [31:0] alu_a = (idex_src_a == 2'd1) ? idex_pc :
                        (idex_src_a == 2'd2) ? 32'd0   : rs1_fwd;
    wire [31:0] alu_b = idex_src_b_imm ? idex_imm : rs2_fwd;
    wire [31:0] alu_result;

    alu u_alu (.a(alu_a), .b(alu_b), .ctrl(idex_alu), .y(alu_result));

    // ---- branch / jump resolution ----
    reg branch_cond;
    always @* begin
        case (idex_funct3)
            3'b000:  branch_cond = (rs1_fwd == rs2_fwd);                    // BEQ
            3'b001:  branch_cond = (rs1_fwd != rs2_fwd);                    // BNE
            3'b100:  branch_cond = ($signed(rs1_fwd) <  $signed(rs2_fwd));  // BLT
            3'b101:  branch_cond = ($signed(rs1_fwd) >= $signed(rs2_fwd));  // BGE
            3'b110:  branch_cond = (rs1_fwd <  rs2_fwd);                    // BLTU
            3'b111:  branch_cond = (rs1_fwd >= rs2_fwd);                    // BGEU
            default: branch_cond = 1'b0;
        endcase
    end

    assign take_branch   = (idex_branch && branch_cond) || idex_jal || idex_jalr;
    assign branch_target = idex_jalr ? {alu_result[31:1], 1'b0}   // rs1 + imm, bit0 cleared
                                     : (idex_pc + idex_imm);      // PC + imm

    // JAL/JALR write PC+4 to rd, everything else writes the ALU result
    wire [31:0] ex_result = (idex_jal || idex_jalr) ? (idex_pc + 32'd4) : alu_result;

    // ---- EX/MEM register ----
    always @(posedge clk) begin
        if (rst) begin
            exmem_reg_write <= 0; exmem_mem_read <= 0; exmem_mem_write <= 0;
            exmem_mem_to_reg <= 0; exmem_rd <= 5'd0; exmem_valid <= 1'b0;
        end else begin
            exmem_valid      <= idex_valid;
            exmem_reg_write  <= idex_reg_write;
            exmem_mem_read   <= idex_mem_read;
            exmem_mem_write  <= idex_mem_write;
            exmem_mem_to_reg <= idex_mem_to_reg;
            exmem_rd         <= idex_rd;
        end
        exmem_result     <= ex_result;
        exmem_store_data <= rs2_fwd;
        exmem_funct3     <= idex_funct3;
    end

    // =================================================================
    // MEM stage
    // =================================================================
    wire [31:0] mem_rdata;
    dmem u_dmem (
        .clk(clk), .mem_write(exmem_mem_write), .funct3(exmem_funct3),
        .addr(exmem_result), .wdata(exmem_store_data), .rdata(mem_rdata)
    );

    // ---- MEM/WB register ----
    reg [31:0] memwb_result, memwb_rdata;
    reg        memwb_mem_to_reg, memwb_valid;
    always @(posedge clk) begin
        if (rst) begin
            memwb_reg_write <= 0; memwb_mem_to_reg <= 0; memwb_rd <= 5'd0; memwb_valid <= 1'b0;
        end else begin
            memwb_valid      <= exmem_valid;
            memwb_reg_write  <= exmem_reg_write;
            memwb_mem_to_reg <= exmem_mem_to_reg;
            memwb_rd         <= exmem_rd;
        end
        memwb_result <= exmem_result;
        memwb_rdata  <= mem_rdata;
    end

    // =================================================================
    // WB stage
    // =================================================================
    assign wb_data = memwb_mem_to_reg ? memwb_rdata : memwb_result;

    // ---- debug outputs ----
    assign dbg_pc     = pc;
    assign dbg_retire = memwb_valid;
endmodule
