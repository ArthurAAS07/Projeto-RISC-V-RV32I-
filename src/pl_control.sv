// =============================================================================
// pl_control.sv
// Unidade de Controle Principal -- RV32I pipelined
//
// Decodifica o opcode de 7 bits (estagio ID) e gera os sinais de controle
// que serao propagados pelos registradores de pipeline.
//
// Suporte original mantido: ADD/SUB/AND/OR/SLT, LW, SW, BEQ.
//
// ADICIONADO - Etapa 1:
//   R-type: XOR, SLL, SRL, SRA, SLTU
//   I-type aritmetico: ADDI, ANDI, ORI, SLTI, SLLI, SRLI, SRAI
//
// ADICIONADO - Etapa 2:
//   Load: LB, LH, LBU, LHU  (LW mantido)
//   Store: SB, SH           (SW mantido)
//   Branch: BNE, BLT, BGE, BLTU, BGEU  (BEQ mantido)
//   Jump: JAL, JALR
//   U-type: LUI, AUIPC
//
// Sinais adicionados:
//   ALUASrc[1:0]  00=rs1/forwarding, 01=PC, 10=zero
//   ResultSrc[1:0] 00=ALU, 01=memoria, 10=PC+4
//   Jump          JAL
//   Jalr          JALR
// =============================================================================

`timescale 1ns / 1ps

module pl_control (
    input  logic [6:0] Opcode,
    output logic [1:0] ALUASrc,
    output logic       ALUSrc,
    output logic [1:0] ResultSrc,
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic       Jump,
    output logic       Jalr,
    output logic [1:0] ALUOp
);

    localparam R_TYPE  = 7'b0110011;
    localparam I_ARITH = 7'b0010011;
    localparam LOAD    = 7'b0000011;
    localparam STORE   = 7'b0100011;
    localparam BRANCH  = 7'b1100011;
    localparam JAL     = 7'b1101111;
    localparam JALR    = 7'b1100111;
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;

    always_comb begin
        ALUASrc   = 2'b00;
        ALUSrc    = 1'b0;
        ResultSrc = 2'b00;
        RegWrite  = 1'b0;
        MemRead   = 1'b0;
        MemWrite  = 1'b0;
        Branch    = 1'b0;
        Jump      = 1'b0;
        Jalr      = 1'b0;
        ALUOp     = 2'b00;

        case (Opcode)
            R_TYPE: begin
                ALUASrc   = 2'b00; // rs1
                ALUSrc    = 1'b0;  // rs2
                ResultSrc = 2'b00; // ALU
                RegWrite  = 1'b1;
                ALUOp     = 2'b10;
            end

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 1: ADDI, ANDI, ORI, SLTI, SLLI, SRLI, SRAI.
            // -----------------------------------------------------------------
            I_ARITH: begin
                ALUASrc   = 2'b00; // rs1
                ALUSrc    = 1'b1;  // imediato I
                ResultSrc = 2'b00; // ALU
                RegWrite  = 1'b1;
                ALUOp     = 2'b11;
            end

            LOAD: begin
                ALUASrc   = 2'b00; // rs1 + imm
                ALUSrc    = 1'b1;
                ResultSrc = 2'b01; // memoria
                RegWrite  = 1'b1;
                MemRead   = 1'b1;
                ALUOp     = 2'b00;
            end

            STORE: begin
                ALUASrc   = 2'b00; // rs1 + imm
                ALUSrc    = 1'b1;
                MemWrite  = 1'b1;
                ALUOp     = 2'b00;
            end

            BRANCH: begin
                Branch    = 1'b1;
                ALUOp     = 2'b01;
            end

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 2: JAL escreve PC+4 e desvia para PC+imm.
            // -----------------------------------------------------------------
            JAL: begin
                ResultSrc = 2'b10; // PC+4
                RegWrite  = 1'b1;
                Jump      = 1'b1;
                ALUOp     = 2'b00;
            end

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 2: JALR escreve PC+4 e desvia para (rs1+imm)&~1.
            // -----------------------------------------------------------------
            JALR: begin
                ALUASrc   = 2'b00; // rs1
                ALUSrc    = 1'b1;  // imediato I
                ResultSrc = 2'b10; // PC+4
                RegWrite  = 1'b1;
                Jalr      = 1'b1;
                ALUOp     = 2'b00;
            end

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 2: LUI escreve o imediato U diretamente.
            // Implementacao: ALU = 0 + imm_U.
            // -----------------------------------------------------------------
            LUI: begin
                ALUASrc   = 2'b10; // zero
                ALUSrc    = 1'b1;  // imediato U
                ResultSrc = 2'b00; // ALU
                RegWrite  = 1'b1;
                ALUOp     = 2'b00;
            end

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 2: AUIPC escreve PC + imediato U.
            // -----------------------------------------------------------------
            AUIPC: begin
                ALUASrc   = 2'b01; // PC
                ALUSrc    = 1'b1;  // imediato U
                ResultSrc = 2'b00; // ALU
                RegWrite  = 1'b1;
                ALUOp     = 2'b00;
            end

            default: ; // sinais permanecem em zero (seguro)
        endcase
    end

endmodule
