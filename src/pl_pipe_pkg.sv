// =============================================================================
// pl_pipe_pkg.sv
// Definicoes dos registradores de pipeline -- processador RV32I pipelined
//
// Quatro registradores de pipeline:
//   IF/ID  : resultado da busca de instrucao
//   ID/EX  : resultado da decodificacao + leitura do banco de registradores
//   EX/MEM : resultado da execucao (ALU)
//   MEM/WB : resultado do acesso a memoria
// =============================================================================

package pl_pipe_pkg;

    // ---- IF/ID --------------------------------------------------------------
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
    } if_id_t;

    // ---- ID/EX --------------------------------------------------------------
    typedef struct packed {
        // sinais de controle propagados para os estagios seguintes
        logic [1:0]  alu_a_src;   // ADICIONADO - Etapa 2: 00=rs1, 01=PC, 10=zero
        logic        alu_src;
        logic [1:0]  result_src;  // ADICIONADO - Etapa 2: 00=ALU, 01=mem, 10=PC+4
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic [1:0]  alu_op;
        logic        branch;
        logic        jump;        // ADICIONADO - Etapa 2: JAL
        logic        jalr;        // ADICIONADO - Etapa 2: JALR
        // dados
        logic [31:0] pc;
        logic [31:0] pc_plus4;    // ADICIONADO - Etapa 2: valor escrito por JAL/JALR
        logic [31:0] rd1;         // saida 1 do banco de registradores
        logic [31:0] rd2;         // saida 2 do banco de registradores
        logic [4:0]  rs1;         // endereco rs1 (para forwarding)
        logic [4:0]  rs2;         // endereco rs2 (para forwarding)
        logic [4:0]  rd;          // registrador destino
        logic [31:0] imm_ext;     // imediato com extensao adequada ao tipo
        logic [2:0]  funct3;
        logic [6:0]  funct7;
    } id_ex_t;

    // ---- EX/MEM -------------------------------------------------------------
    typedef struct packed {
        // sinais de controle
        logic [1:0]  result_src;  // ADICIONADO - Etapa 2: seletor do dado de WB
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        // dados
        logic [31:0] alu_result;
        logic [31:0] write_data;  // valor de rs2 apos forwarding (para store/MMIO)
        logic [31:0] pc_plus4;    // ADICIONADO - Etapa 2: segue ate WB para JAL/JALR
        logic [4:0]  rd;
        logic [2:0]  funct3;      // ADICIONADO - Etapa 2: tamanho/sinal de load/store e branch
    } ex_mem_t;

    // ---- MEM/WB -------------------------------------------------------------
    typedef struct packed {
        // sinais de controle
        logic [1:0]  result_src;  // ADICIONADO - Etapa 2: 00=ALU, 01=mem, 10=PC+4
        logic        reg_write;
        // dados
        logic [31:0] alu_result;
        logic [31:0] read_data;   // dado lido da memoria ja estendido (LB/LH/LBU/LHU/LW)
        logic [31:0] pc_plus4;    // ADICIONADO - Etapa 2: dado de retorno de JAL/JALR
        logic [4:0]  rd;
    } mem_wb_t;

endpackage
