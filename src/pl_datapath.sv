// =============================================================================
// pl_datapath.sv
// Datapath pipeline de 5 estagios -- RV32I
//
// Estagios:
//   IF  -- busca instrucao (pl_imem, PC)
//   ID  -- decodificacao, leitura de registradores, deteccao de hazard
//   EX  -- execucao (ALU), resolucao de branch/jump, forwarding
//   MEM -- acesso a memoria de dados / MMIO
//   WB  -- escrita no banco de registradores
//
// Tratamento de hazards:
//   Load-use stall : 1 ciclo de bolha (pl_hazard)
//   RAW data       : forwarding EX/MEM -> EX e MEM/WB -> EX (pl_forward)
//   Branch/Jump    : flush de IF e ID (2 NOPs) na resolucao em EX
//
// Decodificacao de endereco (estagio MEM):
//   alu_result[10] = 0 -> memoria de dados  (0x000-0x3FF)
//   alu_result[10] = 1 -> MMIO              (0x400-0x7FF)
//     alu_result[4:2] seleciona periferico dentro da janela MMIO
// =============================================================================

`timescale 1ns / 1ps

import pl_pipe_pkg::*;

module pl_datapath (
    input  logic        clk,
    input  logic        rst_n,

    // Sinais de controle vindos do estagio ID (pl_control)
    input  logic [1:0]  ALUASrc,
    input  logic        ALUSrc,
    input  logic [1:0]  ResultSrc,
    input  logic        RegWrite,
    input  logic        MemRead,
    input  logic        MemWrite,
    input  logic        Branch,
    input  logic        Jump,
    input  logic        Jalr,
    input  logic [1:0]  ALUOp,

    // Codigo de operacao da ALU (pl_alu_ctrl, usa campos do estagio EX)
    input  logic [3:0]  ALU_CC,

    // Campos realimentados ao pl_cpu para controle e ALU ctrl
    output logic [6:0]  Opcode,       // opcode do estagio ID (para pl_control)
    output logic [2:0]  Funct3_EX,    // funct3 do estagio EX (para pl_alu_ctrl)
    output logic [6:0]  Funct7_EX,    // funct7 do estagio EX (para pl_alu_ctrl)
    output logic [1:0]  ALUOp_EX,     // ALUOp do estagio EX  (para pl_alu_ctrl)

    output logic [31:0] PC,           // PC atual (testbench / debug)

    // E/S Mapeada em Memoria -- DE2-115
    input  logic [17:0] SW,
    input  logic [3:0]  KEY,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD,

    // Observabilidade para o testbench
    output logic        wb_reg_write,   // pulso quando WB escreve registrador
    output logic [4:0]  wb_reg_dst,     // registrador destino (WB)
    output logic [31:0] wb_reg_data,    // dado escrito (WB)
    output logic        mem_wr_en,      // escrita na dmem (nao MMIO)
    output logic [7:0]  mem_wr_addr,    // endereco de palavra da dmem (MEM)
    output logic [31:0] mem_wr_data     // dado escrito na dmem (MEM)
);

    // =========================================================================
    // Sinais internos
    // =========================================================================

    // PC
    logic [31:0] pc_reg, pc_plus4;

    // Registradores de pipeline
    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    mem_wb_t mem_wb;

    // Hazard / branch / jump
    logic        stall;
    logic        pc_src;
    logic [31:0] branch_target;
    logic        branch_taken;

    // ID
    logic [31:0] rd1, rd2, imm_ext;
    logic        uses_rs1_id, uses_rs2_id;

    // EX -- forwarding
    logic [1:0]  fwd_a, fwd_b;
    logic [31:0] fwd_srca, fwd_srcb;
    logic [31:0] alu_srca, alu_srcb;
    logic [31:0] alu_result;
    logic        zero;

    // WB
    logic [31:0] wb_data;

    // MEM
    logic        mmio_sel;
    logic [31:0] dmem_rd, mmio_rd, mem_read_word, mem_read_data;
    logic [7:0]  load_byte;
    logic [15:0] load_half;

    // Opcodes usados apenas no datapath para decidir hazards reais de rs1/rs2.
    localparam R_TYPE  = 7'b0110011;
    localparam I_ARITH = 7'b0010011;
    localparam LOAD    = 7'b0000011;
    localparam STORE   = 7'b0100011;
    localparam BRANCH  = 7'b1100011;
    localparam JAL     = 7'b1101111;
    localparam JALR    = 7'b1100111;
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;

    // =========================================================================
    // IF -- Busca de instrucao
    // =========================================================================
    logic [31:0] instr_if;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc_reg <= 32'b0;
        else if (pc_src) pc_reg <= branch_target;   // branch/jump tem prioridade
        else if (!stall) pc_reg <= pc_plus4;
        // else stall: PC mantido
    end

    assign PC       = pc_reg;
    assign pc_plus4 = pc_reg + 32'd4;

    pl_imem imem (
        .addr  (pc_reg[9:2]),
        .instr (instr_if)
    );

    // =========================================================================
    // Registrador IF/ID
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                    // reset assicrono (unico sinal na lista)
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (pc_src) begin           // flush sincrono: branch/jump tomado
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (!stall) begin           // avanco normal
            if_id.pc    <= pc_reg;
            if_id.instr <= instr_if;
        end
        // else stall: mantido
    end

    // =========================================================================
    // ID -- Decodificacao, banco de registradores, imediato, hazard
    // =========================================================================
    assign Opcode = if_id.instr[6:0];

    // -------------------------------------------------------------------------
    // ADICIONADO - Etapa 1/2: identifica quais operandos sao realmente lidos.
    // Isso evita stall falso em I-type, JAL, LUI e AUIPC, pois nesses formatos
    // alguns campos ocupam posicoes que parecem rs1/rs2 mas sao imediato/rd.
    // -------------------------------------------------------------------------
    always_comb begin
        uses_rs1_id = 1'b0;
        uses_rs2_id = 1'b0;

        case (Opcode)
            R_TYPE: begin
                uses_rs1_id = 1'b1;
                uses_rs2_id = 1'b1;
            end
            I_ARITH,
            LOAD,
            JALR: begin
                uses_rs1_id = 1'b1;
            end
            STORE,
            BRANCH: begin
                uses_rs1_id = 1'b1;
                uses_rs2_id = 1'b1;
            end
            JAL,
            LUI,
            AUIPC: begin
                uses_rs1_id = 1'b0;
                uses_rs2_id = 1'b0;
            end
            default: begin
                uses_rs1_id = 1'b0;
                uses_rs2_id = 1'b0;
            end
        endcase
    end

    // Deteccao de hazard load-use
    pl_hazard hazard (
        .if_id_rs1       (if_id.instr[19:15]),
        .if_id_rs2       (if_id.instr[24:20]),
        .if_id_uses_rs1  (uses_rs1_id),
        .if_id_uses_rs2  (uses_rs2_id),
        .id_ex_rd        (id_ex.rd),
        .id_ex_mem_read  (id_ex.mem_read),
        .stall           (stall)
    );

    // Dado de write-back (mux WB): usado tambem pelo forwarding MEM/WB->EX
    always_comb begin
        case (mem_wb.result_src)
            2'b01:   wb_data = mem_wb.read_data;   // Load
            2'b10:   wb_data = mem_wb.pc_plus4;    // JAL/JALR
            default: wb_data = mem_wb.alu_result;  // ALU/LUI/AUIPC
        endcase
    end

    pl_regfile regfile (
        .clk       (clk),
        .RegWrite  (mem_wb.reg_write),
        .rs1       (if_id.instr[19:15]),
        .rs2       (if_id.instr[24:20]),
        .rd        (mem_wb.rd),
        .WriteData (wb_data),
        .ReadData1 (rd1),
        .ReadData2 (rd2)
    );

    pl_sign_ext sign_ext (
        .Instr  (if_id.instr),
        .ImmExt (imm_ext)
    );

    // Saidas para o testbench (estagio WB)
    assign wb_reg_write = mem_wb.reg_write;
    assign wb_reg_dst   = mem_wb.rd;
    assign wb_reg_data  = wb_data;

    // =========================================================================
    // Registrador ID/EX
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                      // reset assicrono (unico sinal na lista)
            id_ex.alu_a_src  <= 2'b00;
            id_ex.alu_src    <= 1'b0;
            id_ex.result_src <= 2'b00;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.jump       <= 1'b0;
            id_ex.jalr       <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.pc_plus4   <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
        end else if (stall || pc_src) begin    // NOP sincrono: load-use ou branch/jump
            id_ex.alu_a_src  <= 2'b00;
            id_ex.alu_src    <= 1'b0;
            id_ex.result_src <= 2'b00;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.jump       <= 1'b0;
            id_ex.jalr       <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.pc_plus4   <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
        end else begin
            id_ex.alu_a_src  <= ALUASrc;
            id_ex.alu_src    <= ALUSrc;
            id_ex.result_src <= ResultSrc;
            id_ex.reg_write  <= RegWrite;
            id_ex.mem_read   <= MemRead;
            id_ex.mem_write  <= MemWrite;
            id_ex.alu_op     <= ALUOp;
            id_ex.branch     <= Branch;
            id_ex.jump       <= Jump;
            id_ex.jalr       <= Jalr;
            id_ex.pc         <= if_id.pc;
            id_ex.pc_plus4   <= if_id.pc + 32'd4;
            id_ex.rd1        <= rd1;
            id_ex.rd2        <= rd2;
            id_ex.rs1        <= if_id.instr[19:15];
            id_ex.rs2        <= if_id.instr[24:20];
            id_ex.rd         <= if_id.instr[11:7];
            id_ex.imm_ext    <= imm_ext;
            id_ex.funct3     <= if_id.instr[14:12];
            id_ex.funct7     <= if_id.instr[31:25];
        end
    end

    // Realimentacao para pl_alu_ctrl (usa campos do estagio EX)
    assign Funct3_EX = id_ex.funct3;
    assign Funct7_EX = id_ex.funct7;
    assign ALUOp_EX  = id_ex.alu_op;

    // =========================================================================
    // EX -- Forwarding, ALU, resolucao de branch/jump
    // =========================================================================
    pl_forward forward (
        .id_ex_rs1        (id_ex.rs1),
        .id_ex_rs2        (id_ex.rs2),
        .ex_mem_rd        (ex_mem.rd),
        .mem_wb_rd        (mem_wb.rd),
        .ex_mem_reg_write (ex_mem.reg_write),
        .mem_wb_reg_write (mem_wb.reg_write),
        .forward_a        (fwd_a),
        .forward_b        (fwd_b)
    );

    // Mux de forwarding para rs1
    always_comb begin
        case (fwd_a)
            2'b10:   fwd_srca = ex_mem.alu_result;
            2'b01:   fwd_srca = wb_data;
            default: fwd_srca = id_ex.rd1;
        endcase
    end

    // Mux de forwarding para rs2 (antes do mux ALUSrc)
    always_comb begin
        case (fwd_b)
            2'b10:   fwd_srcb = ex_mem.alu_result;
            2'b01:   fwd_srcb = wb_data;
            default: fwd_srcb = id_ex.rd2;
        endcase
    end

    // -------------------------------------------------------------------------
    // ADICIONADO - Etapa 2: novo mux do operando A da ALU.
    // 00: rs1 com forwarding; 01: PC (AUIPC); 10: zero (LUI).
    // -------------------------------------------------------------------------
    always_comb begin
        case (id_ex.alu_a_src)
            2'b01:   alu_srca = id_ex.pc;
            2'b10:   alu_srca = 32'b0;
            default: alu_srca = fwd_srca;
        endcase
    end

    // Mux ALUSrc: imediato ou registrador
    assign alu_srcb = id_ex.alu_src ? id_ex.imm_ext : fwd_srcb;

    pl_alu alu (
        .SrcA      (alu_srca),
        .SrcB      (alu_srcb),
        .Operation (ALU_CC),
        .ALUResult (alu_result),
        .Zero      (zero)
    );

    // -------------------------------------------------------------------------
    // ADICIONADO - Etapa 2: comparacao de todos os branches B-type.
    // BEQ/BNE usam igualdade; BLT/BGE usam comparacao signed;
    // BLTU/BGEU usam comparacao unsigned.
    // -------------------------------------------------------------------------
    always_comb begin
        case (id_ex.funct3)
            3'b000:  branch_taken = (fwd_srca == fwd_srcb);                         // BEQ
            3'b001:  branch_taken = (fwd_srca != fwd_srcb);                         // BNE
            3'b100:  branch_taken = ($signed(fwd_srca) <  $signed(fwd_srcb));        // BLT
            3'b101:  branch_taken = ($signed(fwd_srca) >= $signed(fwd_srcb));        // BGE
            3'b110:  branch_taken = (fwd_srca <  fwd_srcb);                         // BLTU
            3'b111:  branch_taken = (fwd_srca >= fwd_srcb);                         // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // ADICIONADO - Etapa 2: PC de destino para branch, JAL e JALR.
    // - Branch/JAL: PC + imediato B/J.
    // - JALR: (rs1 + imediato I) com bit 0 zerado, conforme RV32I.
    // -------------------------------------------------------------------------
    always_comb begin
        if (id_ex.jalr)
            branch_target = {alu_result[31:1], 1'b0};
        else
            branch_target = id_ex.pc + id_ex.imm_ext;
    end

    assign pc_src = (id_ex.branch && branch_taken) || id_ex.jump || id_ex.jalr;

    // =========================================================================
    // Registrador EX/MEM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem.result_src <= 2'b00;
            ex_mem.reg_write  <= 1'b0;
            ex_mem.mem_read   <= 1'b0;
            ex_mem.mem_write  <= 1'b0;
            ex_mem.alu_result <= 32'b0;
            ex_mem.write_data <= 32'b0;
            ex_mem.pc_plus4   <= 32'b0;
            ex_mem.rd         <= 5'b0;
            ex_mem.funct3     <= 3'b0;
        end else begin
            ex_mem.result_src <= id_ex.result_src;
            ex_mem.reg_write  <= id_ex.reg_write;
            ex_mem.mem_read   <= id_ex.mem_read;
            ex_mem.mem_write  <= id_ex.mem_write;
            ex_mem.alu_result <= alu_result;
            ex_mem.write_data <= fwd_srcb;   // rs2 adiantado (para store/MMIO)
            ex_mem.pc_plus4   <= id_ex.pc_plus4;
            ex_mem.rd         <= id_ex.rd;
            ex_mem.funct3     <= id_ex.funct3;
        end
    end

    // =========================================================================
    // MEM -- Memoria de dados + MMIO
    // =========================================================================
    assign mmio_sel = ex_mem.alu_result[10];

    pl_dmem dmem (
        .clk         (clk),
        .MemWrite    (ex_mem.mem_write & ~mmio_sel),
        .addr        (ex_mem.alu_result[9:2]),
        .byte_offset (ex_mem.alu_result[1:0]),
        .funct3      (ex_mem.funct3),
        .WriteData   (ex_mem.write_data),
        .ReadData    (dmem_rd)
    );

    pl_mmio mmio (
        .clk       (clk),
        .rst_n     (rst_n),
        .MemWrite  (ex_mem.mem_write &  mmio_sel),
        .MemRead   (ex_mem.mem_read  &  mmio_sel),
        .addr      (ex_mem.alu_result[4:2]),
        .WriteData (ex_mem.write_data),
        .SW        (SW),
        .KEY       (KEY),
        .ReadData  (mmio_rd),
        .LEDR      (LEDR),
        .LEDG      (LEDG),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD)
    );

    assign mem_read_word = mmio_sel ? mmio_rd : dmem_rd;

    // -------------------------------------------------------------------------
    // ADICIONADO - Etapa 2: extracao little-endian para LB/LH/LBU/LHU/LW.
    // O pl_dmem devolve a palavra completa; aqui o dado e alinhado e estendido
    // antes de entrar no MEM/WB.
    // -------------------------------------------------------------------------
    always_comb begin
        case (ex_mem.alu_result[1:0])
            2'b00:   load_byte = mem_read_word[7:0];
            2'b01:   load_byte = mem_read_word[15:8];
            2'b10:   load_byte = mem_read_word[23:16];
            default: load_byte = mem_read_word[31:24];
        endcase
    end

    always_comb begin
        if (ex_mem.alu_result[1])
            load_half = mem_read_word[31:16];
        else
            load_half = mem_read_word[15:0];
    end

    always_comb begin
        case (ex_mem.funct3)
            3'b000:  mem_read_data = {{24{load_byte[7]}}, load_byte};   // LB
            3'b001:  mem_read_data = {{16{load_half[15]}}, load_half};  // LH
            3'b010:  mem_read_data = mem_read_word;                     // LW
            3'b100:  mem_read_data = {24'b0, load_byte};                // LBU
            3'b101:  mem_read_data = {16'b0, load_half};                // LHU
            default: mem_read_data = mem_read_word;
        endcase
    end

    // Saidas de observabilidade para o testbench
    assign mem_wr_en   = ex_mem.mem_write & ~mmio_sel;
    assign mem_wr_addr = ex_mem.alu_result[9:2];
    assign mem_wr_data = ex_mem.write_data;

    // =========================================================================
    // Registrador MEM/WB
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb.result_src <= 2'b00;
            mem_wb.reg_write  <= 1'b0;
            mem_wb.alu_result <= 32'b0;
            mem_wb.read_data  <= 32'b0;
            mem_wb.pc_plus4   <= 32'b0;
            mem_wb.rd         <= 5'b0;
        end else begin
            mem_wb.result_src <= ex_mem.result_src;
            mem_wb.reg_write  <= ex_mem.reg_write;
            mem_wb.alu_result <= ex_mem.alu_result;
            mem_wb.read_data  <= mem_read_data;
            mem_wb.pc_plus4   <= ex_mem.pc_plus4;
            mem_wb.rd         <= ex_mem.rd;
        end
    end

endmodule
