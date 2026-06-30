// =============================================================================
// pl_sign_ext.sv
// Extensao de Imediatos -- RV32I pipelined
//
// Formatos suportados:
//   I-type : imm[11:0]  = inst[31:20]
//   S-type : imm[11:5]  = inst[31:25], imm[4:0] = inst[11:7]
//   B-type : imm[12]=inst[31], imm[11]=inst[7], imm[10:5]=inst[30:25],
//            imm[4:1]=inst[11:8], imm[0]=0
//   U-type : imm[31:12]=inst[31:12], imm[11:0]=0
//   J-type : imm[20]=inst[31], imm[19:12]=inst[19:12], imm[11]=inst[20],
//            imm[10:1]=inst[30:21], imm[0]=0
// =============================================================================

`timescale 1ns / 1ps

module pl_sign_ext (
    input  logic [31:0] Instr,
    output logic [31:0] ImmExt
);

    localparam I_ARITH = 7'b0010011;
    localparam LOAD    = 7'b0000011;
    localparam STORE   = 7'b0100011;
    localparam BRANCH  = 7'b1100011;
    localparam JALR    = 7'b1100111;
    localparam JAL     = 7'b1101111;
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;

    always_comb begin
        case (Instr[6:0])
            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 1: imediatos I-type aritmeticos.
            // ADICIONADO - Etapa 2: JALR tambem usa imediato I-type.
            // -----------------------------------------------------------------
            I_ARITH,
            LOAD,
            JALR:   ImmExt = {{20{Instr[31]}}, Instr[31:20]};

            STORE:  ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};

            BRANCH: ImmExt = {{19{Instr[31]}}, Instr[31], Instr[7],
                               Instr[30:25], Instr[11:8], 1'b0};

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 2: U-type usado por LUI e AUIPC.
            // -----------------------------------------------------------------
            LUI,
            AUIPC:  ImmExt = {Instr[31:12], 12'b0};

            // -----------------------------------------------------------------
            // ADICIONADO - Etapa 2: J-type usado por JAL.
            // -----------------------------------------------------------------
            JAL:    ImmExt = {{11{Instr[31]}}, Instr[31], Instr[19:12],
                               Instr[20], Instr[30:21], 1'b0};

            default: ImmExt = 32'b0;
        endcase
    end

endmodule
