// =============================================================================
// pl_alu.sv
// Unidade Logica e Aritmetica de 32 bits -- RV32I pipelined
//
// Codificacao de operacao (Operation[3:0]):
//   4'd01 : ADD   -- adicao
//   4'd02 : SUB   -- subtracao
//   4'd03 : XOR   -- OU exclusivo bit a bit
//   4'd04 : OR    -- OU bit a bit
//   4'd05 : AND   -- E bit a bit
//   4'd06 : SLL   -- deslocamento logico para esquerda
//   4'd07 : SRL   -- deslocamento logico para direita
//   4'd08 : SRA   -- deslocamento aritmetico para direita
//   4'd11 : SLT   -- set-less-than com sinal
//   4'd12 : SLTU  -- set-less-than sem sinal
// =============================================================================

`timescale 1ns / 1ps

module pl_alu (
    input  logic [31:0] SrcA,
    input  logic [31:0] SrcB,
    input  logic [3:0]  Operation,
    output logic [31:0] ALUResult,
    output logic        Zero
);

    always_comb begin
        case (Operation)
            4'd01:   ALUResult = SrcA + SrcB;
            4'd02:   ALUResult = SrcA - SrcB;

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 1: operacoes R-type e I-type novas.
            // XOR  atende XOR.
            // SLL  atende SLL/SLLI.
            // SRL  atende SRL/SRLI.
            // SRA  atende SRA/SRAI.
            // SLTU atende SLTU.
            // -----------------------------------------------------------------
            4'd03:   ALUResult = SrcA ^ SrcB;
            4'd06:   ALUResult = SrcA << SrcB[4:0];
            4'd07:   ALUResult = SrcA >> SrcB[4:0];
            4'd08:   ALUResult = $signed(SrcA) >>> SrcB[4:0];
            4'd12:   ALUResult = (SrcA < SrcB) ? 32'd1 : 32'd0;

            4'd04:   ALUResult = SrcA | SrcB;
            4'd05:   ALUResult = SrcA & SrcB;
            4'd11:   ALUResult = ($signed(SrcA) < $signed(SrcB)) ? 32'd1 : 32'd0;
            default: ALUResult = 32'b0;
        endcase
    end

    assign Zero = (ALUResult == 32'b0);

endmodule
