// =============================================================================
// pl_control.sv
// Unidade de Controle Principal -- RV32I pipelined (P&H secao 4.4)
// Etapa 01
// Decodifica o opcode de 7 bits (estagio ID) e gera os sinais de controle
// que serao propagados pelos registradores de pipeline.
//
// Instrucoes suportadas:
//   R-type  (0110011): add, sub, or, and, slt, xor, sll, srl, sra, sltu
//   I-type  (0000011): lw
//   I-type  (0010011): addi, andi, ori, slti, slli, srli, srai  <- Etapa 01
//   S-type  (0100011): sw
//   B-type  (1100011): beq
//
// Tabela de sinais de controle:
//   Sinal     | R-type | lw | I-arith | sw | beq
//   ----------|--------|----|---------|----|-----
//   ALUSrc    |   0    |  1 |    1    |  1 |  0    0=reg, 1=imm
//   MemtoReg  |   0    |  1 |    0    |  - |  -    0=ALU, 1=mem
//   RegWrite  |   1    |  1 |    1    |  0 |  0
//   MemRead   |   0    |  1 |    0    |  0 |  0
//   MemWrite  |   0    |  0 |    0    |  1 |  0
//   Branch    |   0    |  0 |    0    |  0 |  1
//   ALUOp[1]  |   1    |  0 |    1    |  0 |  0
//   ALUOp[0]  |   0    |  0 |    1    |  0 |  1
// =============================================================================
// Sinais novos (Etapa 02):
//   Jump       : desvio incondicional (JAL/JALR) — forca pc_src=1
//   JumpReg    : JALR — alvo = rs1+imm em vez de PC+imm
//   UsePC      : AUIPC — SrcA recebe PC no estagio EX
//   LuiPass    : LUI  — resultado = imm_ext (ignora ALU)
//   JumpResult : JAL/JALR — rd recebe PC+4
//
// Loads/stores parciais (LB/LH/LBU/LHU, SB/SH) usam o mesmo opcode e
// sinais de LW/SW. A largura e tratada no datapath via funct3.
// Branches extras (BNE/BLT/BGE/BLTU/BGEU) usam o mesmo opcode de BEQ.
// =============================================================================

`timescale 1ns / 1ps

module pl_control (
    input  logic [6:0] Opcode,
    output logic       ALUSrc,
    output logic       MemtoReg,
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic [1:0] ALUOp,
    // sinais novos — Etapa 02
    output logic       Jump,
    output logic       JumpReg,
    output logic       UsePC,
    output logic       LuiPass,
    output logic       JumpResult
);

    localparam R_TYPE  = 7'b0110011;
    localparam LOAD    = 7'b0000011;  // LW, LB, LH, LBU, LHU
    localparam I_ARITH = 7'b0010011;  //  Etapa 01: addi, andi, ori, slti, slli, srai
    localparam STORE   = 7'b0100011;  // SW, SB, SH
    localparam BRANCH  = 7'b1100011;  // BEQ, BNE, BLT, BGE, BLTU, BGEU
    localparam JAL     = 7'b1101111;
    localparam JALR    = 7'b1100111;
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;

    always_comb begin
        ALUSrc     = 1'b0;
        MemtoReg   = 1'b0;
        RegWrite   = 1'b0;
        MemRead    = 1'b0;
        MemWrite   = 1'b0;
        Branch     = 1'b0;
        ALUOp      = 2'b00;
        Jump       = 1'b0; // desvio incondicional
        JumpReg    = 1'b0; 
        UsePC      = 1'b0;
        LuiPass    = 1'b0;
        JumpResult = 1'b0; //rd = PC + 4

        case (Opcode)
            R_TYPE: begin
                // ALUSrc   = 1'b0;
                // MemtoReg = 1'b0;
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
            end
            LOAD: begin
                ALUSrc   = 1'b1;
                MemtoReg = 1'b1;
                RegWrite = 1'b1;
                MemRead  = 1'b1;
                // ALUOp    = 2'b00;
            end
            I_ARITH: begin             // Etapa 01
                ALUSrc   = 1'b1;       // SrcB vem do imediato
                // MemtoReg = 1'b0;      
                RegWrite = 1'b1;       // escreve em rd
                ALUOp    = 2'b11;      // pl_alu_ctrl decodifica via Funct3
            end
            STORE: begin
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
                ALUOp    = 2'b00; // ADD para calcular o endereço
            end
            BRANCH: begin
                Branch   = 1'b1;
                ALUOp    = 2'b01;
            end

            JAL: begin
                RegWrite   = 1'b1;
                Jump       = 1'b1;  // desvio incondicional
                JumpResult = 1'b1;  // rd = PC+4
                ALUOp      = 2'b00;
            end

            JALR: begin
                ALUSrc     = 1'b1;  // SrcB = imm (calcula rs1+imm)
                RegWrite   = 1'b1;
                Jump       = 1'b1;
                JumpReg    = 1'b1;  // alvo = rs1+imm
                JumpResult = 1'b1;  // rd = PC+4
                ALUOp      = 2'b00;
            end

            LUI: begin
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
                LuiPass  = 1'b1;    // resultado = imm_ext diretamente
            end

            AUIPC: begin
                ALUSrc   = 1'b1;
                RegWrite = 1'b1;
                UsePC    = 1'b1;    // SrcA = PC
                ALUOp    = 2'b00;   // ADD: PC + imm
            end
            default: ; // sinais permanecem em zero (seguro)
        endcase
    end

endmodule
