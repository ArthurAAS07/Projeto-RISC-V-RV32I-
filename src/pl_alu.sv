// =============================================================================
// pl_alu.sv
// Unidade Logica e Aritmetica de 32 bits -- RV32I pipelined
//
// Codificacao de operacao (Operation[3:0]):
//   4'd01 : ADD  -- adicao com sinal
//   4'd02 : SUB  -- subtracao com sinal  (BEQ usa Zero)
//   4'd04 : OR   -- OU bit a bit
//   4'd05 : AND  -- E bit a bit
//   4'd11 : SLT  -- set-less-than com sinal
//   --- Etapa 01 ---
//   4'd06 : XOR  -- OU exclusivo bit a bit
//   4'd07 : SLL  -- shift left logical
//   4'd08 : SRL  -- shift right logical
//   4'd09 : SRA  -- shift right arithmetic
//   4'd10 : SLTU -- set-less-than sem sinal
// =============================================================================

`timescale 1ns / 1ps

module pl_alu (
    input  logic [31:0] SrcA,
    input  logic [31:0] SrcB,
    input  logic [3:0]  Operation,
    output logic [31:0] ALUResult,
    output logic        Zero
);

    // shamt: para instrucoes de shift, apenas os 5 bits menos significativos
    logic [4:0] shamt;
    assign shamt = SrcB[4:0];

    always_comb begin
        case (Operation)
            // --- operacoes existentes ---
            4'd01:   ALUResult = $signed(SrcA) + $signed(SrcB);
            4'd02:   ALUResult = $signed(SrcA) - $signed(SrcB);
            4'd04:   ALUResult = SrcA | SrcB;
            4'd05:   ALUResult = SrcA & SrcB;
            4'd11:   ALUResult = 32'($signed(SrcA) < $signed(SrcB));

            // --- Etapa 01: novas operacoes ---
            4'd06:   ALUResult = SrcA ^ SrcB;                       // XOR
            4'd07:   ALUResult = SrcA << shamt;                      // SLL
            4'd08:   ALUResult = SrcA >> shamt;                      // SRL (logico)
            4'd09:   ALUResult = 32'($signed(SrcA) >>> shamt);       // SRA (aritmetico)
            4'd10:   ALUResult = 32'(SrcA < SrcB);                   // SLTU (sem sinal)

            default: ALUResult = 32'b0;
        endcase
    end

    assign Zero = (ALUResult == 32'b0);

endmodule
