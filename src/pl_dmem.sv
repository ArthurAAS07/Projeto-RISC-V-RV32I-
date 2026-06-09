// =============================================================================
// pl_dmem.sv
// Memoria de dados -- RV32I pipelined
//
// Capacidade : 256 palavras x 32 bits = 1 KB
// Init file  : data.mif   (sintese Quartus)
//              data.hex   (simulacao ModelSim via $readmemh)
//
// Leitura  : assincrona (combinatorial) -- disponivel no estagio MEM
// Escrita  : sincrona (posedge clk, gated por MemWrite & ~mmio_sel)
// Endereco : alu_result[9:2]  (endereco de palavra de 8 bits)
//
// Instrucoes de store suportadas (via funct3):
//   funct3 = 3'b000 : SB -- escreve 1 byte  (byte selecionado por byte_offset)
//   funct3 = 3'b001 : SH -- escreve 2 bytes (halfword selecionada por byte_offset[1])
//   funct3 = 3'b010 : SW -- escreve 4 bytes (comportamento original)
// =============================================================================

`timescale 1ns / 1ps

module pl_dmem (
    input  logic        clk,
    input  logic        MemWrite,
    input  logic [7:0]  addr,
    input  logic [1:0]  byte_offset,  // bits [1:0] do endereco -- seleciona byte/halfword
    input  logic [2:0]  funct3,       // 000=SB, 001=SH, 010=SW
    input  logic [31:0] WriteData,
    output logic [31:0] ReadData
);

    (* ram_init_file = "data.mif" *) logic [31:0] ram [0:255];

    // synthesis translate_off
    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'h00000000;
        $readmemh("data.hex", ram);
    end
    // synthesis translate_on

    always@(posedge clk) begin
        if (MemWrite) begin
            case (funct3)
                3'b000: begin // SB -- escreve apenas 1 byte
                    case (byte_offset)
                        2'b00: ram[addr][ 7: 0] <= WriteData[7:0];
                        2'b01: ram[addr][15: 8] <= WriteData[7:0];
                        2'b10: ram[addr][23:16] <= WriteData[7:0];
                        2'b11: ram[addr][31:24] <= WriteData[7:0];
                    endcase
                end
                3'b001: begin // SH -- escreve halfword (2 bytes)
                    case (byte_offset[1])
                        1'b0: ram[addr][15: 0] <= WriteData[15:0];
                        1'b1: ram[addr][31:16] <= WriteData[15:0];
                    endcase
                end
                default: // SW (funct3=010) -- escreve palavra inteira (original)
                    ram[addr] <= WriteData;
            endcase
        end
    end

    assign ReadData = ram[addr];

endmodule
