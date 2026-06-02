// =============================================================================
// pl_sign_ext.sv
// Extensao de Sinal de Imediatos -- RV32I pipelined (P&H secao 4.4)
//
// Formatos suportados:
//   I-type lw    (0000011): imm[11:0]  = inst[31:20]
//   I-type arith (0010011): imm[11:0]  = inst[31:20]  <- Etapa 01
//     Nota: para SLLI/SRLI/SRAI, inst[31:20] = {funct7[6:0], shamt[4:0]}
//           a ALU usa apenas SrcB[4:0] como shamt, portanto esta correta.
//   S-type (sw)  (0100011): imm[11:5]  = inst[31:25], imm[4:0] = inst[11:7]
//   B-type (beq) (1100011): imm[12]=inst[31], imm[11]=inst[7], imm[10:5]=inst[30:25],
//                            imm[4:1]=inst[11:8], imm[0]=0
// =============================================================================

`timescale 1ns / 1ps

module pl_sign_ext (
    input  logic [31:0] Instr,
    output logic [31:0] ImmExt
);

    localparam LOAD    = 7'b0000011;
    localparam I_ARITH = 7'b0010011;   // Etapa 01
    localparam STORE   = 7'b0100011;
    localparam BRANCH  = 7'b1100011;

    always_comb begin
        case (Instr[6:0])
            LOAD,
            I_ARITH: ImmExt = {{20{Instr[31]}}, Instr[31:20]};  // I-type

            STORE:   ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};

            BRANCH:  ImmExt = {{19{Instr[31]}}, Instr[31], Instr[7],
                                Instr[30:25], Instr[11:8], 1'b0};

            default: ImmExt = 32'b0;
        endcase
    end

endmodule
