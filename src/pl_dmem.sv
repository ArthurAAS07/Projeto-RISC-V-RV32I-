// =============================================================================
// pl_dmem.sv
// Memoria de dados -- RV32I pipelined
//
// Capacidade : 256 palavras x 32 bits = 1 KB
// Init file  : data.mif   (sintese Quartus)
//              data.hex   (simulacao ModelSim via $readmemh)
//
// Leitura  : assincrona (combinatorial) -- devolve a palavra de 32 bits.
// Escrita  : sincrona (posedge clk), com suporte a byte/half/word.
// Endereco : addr = alu_result[9:2] e byte_offset = alu_result[1:0].
// =============================================================================

`timescale 1ns / 1ps

module pl_dmem (
    input  logic        clk,
    input  logic        MemWrite,
    input  logic [7:0]  addr,

    // -------------------------------------------------------------------------
    // ADICIONADO - Etapa 2: suporte a SB, SH e SW.
    // byte_offset seleciona o byte dentro da palavra de 32 bits.
    // funct3 identifica o tamanho do store: 000=SB, 001=SH, 010=SW.
    // -------------------------------------------------------------------------
    input  logic [1:0]  byte_offset,
    input  logic [2:0]  funct3,

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

    always_ff @(posedge clk) begin
        if (MemWrite) begin
            case (funct3)
                // -------------------------------------------------------------
                // ADICIONADO - Etapa 2: SB (store byte), little-endian.
                // -------------------------------------------------------------
                3'b000: begin
                    case (byte_offset)
                        2'b00: ram[addr][7:0]   <= WriteData[7:0];
                        2'b01: ram[addr][15:8]  <= WriteData[7:0];
                        2'b10: ram[addr][23:16] <= WriteData[7:0];
                        2'b11: ram[addr][31:24] <= WriteData[7:0];
                    endcase
                end

                // -------------------------------------------------------------
                // ADICIONADO - Etapa 2: SH (store halfword), little-endian.
                // Enderecos alinhados em 0 ou 2 sao os casos esperados.
                // -------------------------------------------------------------
                3'b001: begin
                    if (byte_offset[1])
                        ram[addr][31:16] <= WriteData[15:0];
                    else
                        ram[addr][15:0]  <= WriteData[15:0];
                end

                // SW original mantido.
                3'b010: ram[addr] <= WriteData;

                default: ram[addr] <= WriteData;
            endcase
        end
    end

    assign ReadData = ram[addr];

endmodule
