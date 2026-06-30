// =============================================================================
// pl_alu_ctrl.sv
// Unidade de Controle da ALU -- RV32I pipelined
//
// Entradas (do estagio EX -- registrador ID/EX):
//   ALUOp[1:0] : codigo do controlador principal
//     2'b00 : Load/Store/JALR/LUI/AUIPC -> forcar ADD
//     2'b01 : Branch                    -> forcar SUB
//     2'b10 : R-type                    -> decodificar via Funct3/Funct7
//     2'b11 : I-type aritmetico         -> decodificar via Funct3/Funct7
//
// Saida Operation[3:0] -> pl_alu.sv:
//   ADD, SUB, XOR, OR, AND, SLL, SRL, SRA, SLT, SLTU
// =============================================================================

`timescale 1ns / 1ps

module pl_alu_ctrl (
    input  logic [1:0] ALUOp,
    input  logic [6:0] Funct7,
    input  logic [2:0] Funct3,
    output logic [3:0] Operation
);

    always_comb begin
        case (ALUOp)
            2'b00: Operation = 4'd01;   // Load/Store/JALR/LUI/AUIPC -> ADD

            2'b01: Operation = 4'd02;   // Branch -> SUB (comparacao tambem e feita no datapath)

            2'b10: begin                // R-type: decodificar Funct
                case (Funct3)
                    3'h0: Operation = Funct7[5] ? 4'd02 : 4'd01; // SUB ou ADD

                    // ---------------------------------------------------------
                    // ADICIONADO - Etapa 1: novas instrucoes R-type.
                    // ---------------------------------------------------------
                    3'h4: Operation = 4'd03;                    // XOR
                    3'h1: Operation = 4'd06;                    // SLL
                    3'h5: Operation = Funct7[5] ? 4'd08 : 4'd07; // SRA ou SRL
                    3'h3: Operation = 4'd12;                    // SLTU

                    3'h6: Operation = 4'd04;                    // OR
                    3'h7: Operation = 4'd05;                    // AND
                    3'h2: Operation = 4'd11;                    // SLT
                    default: Operation = 4'd01;
                endcase
            end

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 1: I-type aritmetico.
            // ADDI usa ADD; ANDI/ORI usam AND/OR; SLTI usa SLT;
            // SLLI/SRLI/SRAI usam o shamt em SrcB[4:0].
            // -----------------------------------------------------------------
            2'b11: begin
                case (Funct3)
                    3'h0: Operation = 4'd01;                    // ADDI
                    3'h7: Operation = 4'd05;                    // ANDI
                    3'h6: Operation = 4'd04;                    // ORI
                    3'h2: Operation = 4'd11;                    // SLTI
                    3'h1: Operation = 4'd06;                    // SLLI
                    3'h5: Operation = Funct7[5] ? 4'd08 : 4'd07; // SRAI ou SRLI
                    default: Operation = 4'd01;
                endcase
            end

            default: Operation = 4'd01;
        endcase
    end

endmodule
