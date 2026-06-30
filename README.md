# Projeto RISC-V RV32I Pipelined — Etapas 1 e 2

Este projeto implementa uma CPU RISC-V de 32 bits, compatível com um subconjunto da ISA **RV32I**, usando **SystemVerilog** e uma arquitetura **pipeline de 5 estágios**. O projeto foi preparado para compilação no **Quartus Prime 21.1** e execução na FPGA, mantendo a organização original do processador e adicionando as instruções solicitadas nas Etapas 1 e 2 do projeto.

As modificações foram feitas **somente nos arquivos da pasta `src/`** e os trechos adicionados foram separados por comentários no código para facilitar a identificação durante a apresentação e a correção.

---

## 1. Visão geral da CPU

A CPU segue a organização clássica de um processador RISC-V com pipeline de 5 estágios:

```text
+------+     +------+     +------+     +------+     +------+
|  IF  | --> |  ID  | --> |  EX  | --> | MEM  | --> |  WB  |
+------+     +------+     +------+     +------+     +------+
  Busca      Decode       Execução     Memória     Escrita
  instrução  Registros    ALU/Branch   dmem/MMIO   Regfile
```

### Estágios do pipeline

| Estágio | Nome | Função |
|---|---|---|
| IF | Instruction Fetch | Busca a instrução na memória de instruções usando o PC. |
| ID | Instruction Decode | Decodifica a instrução, lê registradores e gera imediato. |
| EX | Execute | Executa a operação da ALU, compara branches e calcula destino de salto. |
| MEM | Memory Access | Acessa a memória de dados ou periféricos mapeados em memória. |
| WB | Write Back | Escreve o resultado final no banco de registradores. |

Os registradores intermediários do pipeline são definidos em `pl_pipe_pkg.sv`:

```text
IF/ID  -> guarda PC e instrução buscada
ID/EX  -> guarda sinais de controle, registradores lidos, imediato e campos da instrução
EX/MEM -> guarda resultado da ALU, dado para store e controles de memória
MEM/WB -> guarda dado que será escrito de volta no registrador destino
```

---

## 2. Instruções suportadas após as modificações

A implementação original já possuía suporte a instruções básicas como `ADD`, `SUB`, `AND`, `OR`, `SLT`, `LW`, `SW` e `BEQ`. Nas Etapas 1 e 2, foram adicionadas as instruções abaixo.

### Etapa 1 — Aritmética, lógica e deslocamentos

#### R-type

| Instrução | Função |
|---|---|
| `XOR` | Ou exclusivo bit a bit. |
| `SLL` | Deslocamento lógico para a esquerda. |
| `SRL` | Deslocamento lógico para a direita. |
| `SRA` | Deslocamento aritmético para a direita. |
| `SLTU` | Comparação menor que sem sinal. |

#### I-type aritmético

| Instrução | Função |
|---|---|
| `ADDI` | Soma registrador com imediato. |
| `ANDI` | AND bit a bit com imediato. |
| `ORI` | OR bit a bit com imediato. |
| `SLTI` | Compara registrador com imediato com sinal. |
| `SLLI` | Deslocamento lógico imediato para a esquerda. |
| `SRLI` | Deslocamento lógico imediato para a direita. |
| `SRAI` | Deslocamento aritmético imediato para a direita. |

### Etapa 2 — Memória, desvios, jumps e U-type

#### Loads

| Instrução | Função |
|---|---|
| `LB` | Carrega 1 byte com extensão de sinal. |
| `LH` | Carrega 2 bytes com extensão de sinal. |
| `LBU` | Carrega 1 byte com extensão por zero. |
| `LHU` | Carrega 2 bytes com extensão por zero. |

#### Stores

| Instrução | Função |
|---|---|
| `SB` | Armazena 1 byte na memória. |
| `SH` | Armazena 2 bytes na memória. |

#### Branches

| Instrução | Função |
|---|---|
| `BNE` | Desvia se os registradores forem diferentes. |
| `BLT` | Desvia se `rs1 < rs2`, usando comparação com sinal. |
| `BGE` | Desvia se `rs1 >= rs2`, usando comparação com sinal. |
| `BLTU` | Desvia se `rs1 < rs2`, usando comparação sem sinal. |
| `BGEU` | Desvia se `rs1 >= rs2`, usando comparação sem sinal. |

#### Jumps

| Instrução | Função |
|---|---|
| `JAL` | Salta para `PC + imediato` e salva `PC + 4` em `rd`. |
| `JALR` | Salta para `(rs1 + imediato) & ~1` e salva `PC + 4` em `rd`. |

#### U-type

| Instrução | Função |
|---|---|
| `LUI` | Escreve o imediato superior em `rd`, ou seja, `imm << 12`. |
| `AUIPC` | Soma o imediato superior ao PC atual e escreve o resultado em `rd`. |

---

## 3. Arquivos modificados

As alterações foram concentradas nos seguintes arquivos da pasta `src/`:

```text
src/
├── pl_alu.sv
├── pl_alu_ctrl.sv
├── pl_control.sv
├── pl_cpu.sv
├── pl_datapath.sv
├── pl_dmem.sv
├── pl_hazard.sv
├── pl_pipe_pkg.sv
└── pl_sign_ext.sv
```

Nenhum arquivo fora da pasta `src/` foi alterado.

---

## 4. Explicação das modificações por arquivo

### 4.1 `pl_alu.sv`

A ALU foi expandida para executar as novas operações da Etapa 1.

Foram adicionados novos códigos de operação internos:

```systemverilog
4'd03 : XOR
4'd06 : SLL
4'd07 : SRL
4'd08 : SRA
4'd12 : SLTU
```

O trecho principal adicionado foi:

```systemverilog
4'd03:   ALUResult = SrcA ^ SrcB;
4'd06:   ALUResult = SrcA << SrcB[4:0];
4'd07:   ALUResult = SrcA >> SrcB[4:0];
4'd08:   ALUResult = $signed(SrcA) >>> SrcB[4:0];
4'd12:   ALUResult = (SrcA < SrcB) ? 32'd1 : 32'd0;
```

Nos deslocamentos, foi usado `SrcB[4:0]` porque, em uma arquitetura de 32 bits, só são necessários 5 bits para representar deslocamentos de 0 a 31 posições.

---

### 4.2 `pl_alu_ctrl.sv`

A unidade de controle da ALU foi modificada para reconhecer mais combinações de `funct3`, `funct7` e `ALUOp`.

Antes, o controle distinguia basicamente operações R-type originais, loads/stores e branch. Agora ele também trata:

- novas instruções R-type;
- instruções I-type aritméticas;
- deslocamentos imediatos.

Foi adicionado o caso `ALUOp = 2'b11` para instruções I-type aritméticas:

```systemverilog
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
```

Também foram adicionadas as operações R-type:

```systemverilog
3'h4: Operation = 4'd03;                     // XOR
3'h1: Operation = 4'd06;                     // SLL
3'h5: Operation = Funct7[5] ? 4'd08 : 4'd07; // SRA ou SRL
3'h3: Operation = 4'd12;                     // SLTU
```

---

### 4.3 `pl_control.sv`

A unidade de controle principal foi uma das partes mais importantes da modificação. Ela passou a reconhecer novos opcodes e gerar novos sinais de controle.

Foram adicionados os opcodes:

```systemverilog
localparam I_ARITH = 7'b0010011;
localparam JAL     = 7'b1101111;
localparam JALR    = 7'b1100111;
localparam LUI     = 7'b0110111;
localparam AUIPC   = 7'b0010111;
```

Também foram adicionados novos sinais:

| Sinal | Função |
|---|---|
| `ALUASrc` | Escolhe a entrada A da ALU: `rs1`, `PC` ou zero. |
| `ResultSrc` | Escolhe o dado que volta para o registrador: ALU, memória ou `PC+4`. |
| `Jump` | Indica instrução `JAL`. |
| `Jalr` | Indica instrução `JALR`. |

Exemplo de controle para `LUI`:

```systemverilog
LUI: begin
    ALUASrc   = 2'b10; // zero
    ALUSrc    = 1'b1;  // imediato U
    ResultSrc = 2'b00; // ALU
    RegWrite  = 1'b1;
    ALUOp     = 2'b00;
end
```

Exemplo de controle para `AUIPC`:

```systemverilog
AUIPC: begin
    ALUASrc   = 2'b01; // PC
    ALUSrc    = 1'b1;  // imediato U
    ResultSrc = 2'b00; // ALU
    RegWrite  = 1'b1;
    ALUOp     = 2'b00;
end
```

Exemplo de controle para `JAL` e `JALR`:

```systemverilog
JAL: begin
    ResultSrc = 2'b10; // PC+4
    RegWrite  = 1'b1;
    Jump      = 1'b1;
end

JALR: begin
    ALUASrc   = 2'b00; // rs1
    ALUSrc    = 1'b1;  // imediato I
    ResultSrc = 2'b10; // PC+4
    RegWrite  = 1'b1;
    Jalr      = 1'b1;
end
```

---

### 4.4 `pl_cpu.sv`

O arquivo `pl_cpu.sv` funciona como wrapper da CPU. Ele conecta:

- `pl_control`;
- `pl_alu_ctrl`;
- `pl_datapath`.

Como novos sinais de controle foram criados, esse arquivo precisou ser atualizado para declarar e conectar esses sinais:

```systemverilog
logic [1:0] ALUASrc;
logic       ALUSrc;
logic [1:0] ResultSrc;
logic       RegWrite, MemRead, MemWrite, Branch, Jump, Jalr;
logic [1:0] ALUOp;
```

Esses sinais são gerados pela unidade de controle principal e enviados ao datapath.

---

### 4.5 `pl_datapath.sv`

O datapath recebeu as alterações necessárias para que as novas instruções funcionassem dentro do pipeline.

#### Novo mux da entrada A da ALU

Foi criado um mux para escolher a origem da entrada A da ALU:

```systemverilog
always_comb begin
    case (id_ex.alu_a_src)
        2'b01:   alu_srca = id_ex.pc;
        2'b10:   alu_srca = 32'b0;
        default: alu_srca = fwd_srca;
    endcase
end
```

Esse mux permite implementar:

- instruções normais usando `rs1`;
- `AUIPC`, usando `PC`;
- `LUI`, usando zero.

#### Novo mux de write-back

O write-back passou a poder escolher entre três fontes:

```systemverilog
case (mem_wb.result_src)
    2'b01:   wb_data = mem_wb.read_data;   // Load
    2'b10:   wb_data = mem_wb.pc_plus4;    // JAL/JALR
    default: wb_data = mem_wb.alu_result;  // ALU/LUI/AUIPC
endcase
```

Isso é necessário porque `JAL` e `JALR` precisam escrever o endereço de retorno, que é `PC + 4`, no registrador destino.

#### Comparação dos branches

Foram adicionadas as comparações de todos os branches da Etapa 2:

```systemverilog
case (id_ex.funct3)
    3'b000:  branch_taken = (fwd_srca == fwd_srcb);                  // BEQ
    3'b001:  branch_taken = (fwd_srca != fwd_srcb);                  // BNE
    3'b100:  branch_taken = ($signed(fwd_srca) <  $signed(fwd_srcb)); // BLT
    3'b101:  branch_taken = ($signed(fwd_srca) >= $signed(fwd_srcb)); // BGE
    3'b110:  branch_taken = (fwd_srca <  fwd_srcb);                  // BLTU
    3'b111:  branch_taken = (fwd_srca >= fwd_srcb);                  // BGEU
    default: branch_taken = 1'b0;
endcase
```

A diferença principal é que `BLT` e `BGE` usam comparação com sinal, enquanto `BLTU` e `BGEU` usam comparação sem sinal.

#### Cálculo de destino de branch, JAL e JALR

O destino do próximo PC passou a considerar também saltos:

```systemverilog
if (id_ex.jalr)
    branch_target = {alu_result[31:1], 1'b0};
else
    branch_target = id_ex.pc + id_ex.imm_ext;
```

Para `JALR`, o bit menos significativo do destino é zerado, como especificado pela ISA RISC-V.

#### Loads menores que palavra

A memória de dados retorna uma palavra completa de 32 bits. O datapath passou a selecionar o byte ou halfword correto e fazer a extensão adequada:

```systemverilog
case (ex_mem.funct3)
    3'b000:  mem_read_data = {{24{load_byte[7]}}, load_byte};   // LB
    3'b001:  mem_read_data = {{16{load_half[15]}}, load_half};  // LH
    3'b010:  mem_read_data = mem_read_word;                     // LW
    3'b100:  mem_read_data = {24'b0, load_byte};                // LBU
    3'b101:  mem_read_data = {16'b0, load_half};                // LHU
    default: mem_read_data = mem_read_word;
endcase
```

---

### 4.6 `pl_dmem.sv`

A memória de dados foi modificada para aceitar escritas menores que uma palavra de 32 bits.

Antes, o store escrevia sempre uma palavra inteira. Agora o tamanho da escrita é escolhido pelo `funct3`:

| `funct3` | Instrução | Tamanho |
|---|---|---|
| `000` | `SB` | 1 byte |
| `001` | `SH` | 2 bytes |
| `010` | `SW` | 4 bytes |

Trecho do `SB`:

```systemverilog
3'b000: begin
    case (byte_offset)
        2'b00: ram[addr][7:0]   <= WriteData[7:0];
        2'b01: ram[addr][15:8]  <= WriteData[7:0];
        2'b10: ram[addr][23:16] <= WriteData[7:0];
        2'b11: ram[addr][31:24] <= WriteData[7:0];
    endcase
end
```

Trecho do `SH`:

```systemverilog
3'b001: begin
    if (byte_offset[1])
        ram[addr][31:16] <= WriteData[15:0];
    else
        ram[addr][15:0]  <= WriteData[15:0];
end
```

A memória foi tratada em formato **little-endian**, ou seja, os bytes menos significativos ficam nos endereços menores.

---

### 4.7 `pl_hazard.sv`

A unidade de hazard foi ajustada para evitar stalls falsos.

No pipeline, existe hazard do tipo load-use quando uma instrução logo após um load precisa usar o registrador que ainda está sendo carregado. O problema é que algumas instruções possuem campos que parecem `rs1` ou `rs2`, mas na verdade são parte do imediato.

Por isso foram adicionados os sinais:

```systemverilog
input logic if_id_uses_rs1;
input logic if_id_uses_rs2;
```

A nova lógica de stall ficou:

```systemverilog
assign stall = id_ex_mem_read && (id_ex_rd != 5'b0) &&
               ((if_id_uses_rs1 && (id_ex_rd == if_id_rs1)) ||
                (if_id_uses_rs2 && (id_ex_rd == if_id_rs2)));
```

Assim, a CPU só insere bolha quando a instrução realmente usa o registrador que depende do load anterior.

---

### 4.8 `pl_pipe_pkg.sv`

Os registradores de pipeline foram atualizados para transportar os novos sinais entre os estágios.

Foram adicionados campos como:

```systemverilog
logic [1:0] alu_a_src;
logic [1:0] result_src;
logic       jump;
logic       jalr;
logic [31:0] pc_plus4;
logic [2:0] funct3;
```

Esses campos são necessários porque várias decisões acontecem em estágios diferentes. Por exemplo:

- `funct3` é decodificado em ID, mas usado em MEM para `LB`, `LH`, `LBU`, `LHU`, `SB` e `SH`;
- `pc_plus4` é calculado no início do pipeline, mas só é escrito no registrador destino no estágio WB para `JAL` e `JALR`;
- `jump` e `jalr` são gerados no controle, mas afetam o PC no estágio EX.

---

### 4.9 `pl_sign_ext.sv`

A extensão de imediatos foi expandida para suportar os novos formatos de instrução.

Além dos formatos I, S e B, foram adicionados:

#### U-type

Usado por `LUI` e `AUIPC`:

```systemverilog
LUI,
AUIPC: ImmExt = {Instr[31:12], 12'b0};
```

#### J-type

Usado por `JAL`:

```systemverilog
JAL: ImmExt = {{11{Instr[31]}}, Instr[31], Instr[19:12],
               Instr[20], Instr[30:21], 1'b0};
```

#### I-type ampliado

O imediato I-type passou a ser usado também por instruções aritméticas imediatas e por `JALR`:

```systemverilog
I_ARITH,
LOAD,
JALR: ImmExt = {{20{Instr[31]}}, Instr[31:20]};
```

---

## 5. Funcionamento das instruções adicionadas

### 5.1 Instruções R-type

As instruções R-type usam dois registradores fonte, `rs1` e `rs2`, e escrevem o resultado em `rd`.

Fluxo no pipeline:

```text
ID: lê rs1 e rs2
EX: ALU executa a operação escolhida por funct3/funct7
WB: resultado da ALU é escrito em rd
```

Instruções adicionadas:

```text
XOR, SLL, SRL, SRA, SLTU
```

---

### 5.2 Instruções I-type aritméticas

As instruções I-type aritméticas usam `rs1` e um imediato.

Fluxo no pipeline:

```text
ID: lê rs1 e gera imediato I-type
EX: ALU usa rs1 + imediato ou operação lógica/deslocamento
WB: resultado da ALU é escrito em rd
```

Instruções adicionadas:

```text
ADDI, ANDI, ORI, SLTI, SLLI, SRLI, SRAI
```

---

### 5.3 Loads

As instruções de load calculam o endereço no estágio EX e acessam a memória no estágio MEM.

Fluxo no pipeline:

```text
ID: lê registrador base rs1 e gera imediato
EX: calcula endereço = rs1 + imediato
MEM: lê palavra da memória
MEM: seleciona byte/halfword/word e faz extensão de sinal ou zero
WB: escreve o valor carregado em rd
```

Instruções adicionadas:

```text
LB, LH, LBU, LHU
```

---

### 5.4 Stores

As instruções de store calculam o endereço no estágio EX e escrevem na memória no estágio MEM.

Fluxo no pipeline:

```text
ID: lê registrador base rs1 e registrador de dado rs2
EX: calcula endereço = rs1 + imediato
MEM: escreve byte, halfword ou word na memória
```

Instruções adicionadas:

```text
SB, SH
```

---

### 5.5 Branches

Os branches são resolvidos no estágio EX. Quando um branch é tomado, o PC recebe o endereço de destino e as instruções que estavam em IF e ID são descartadas por flush.

Fluxo no pipeline:

```text
ID: lê rs1 e rs2, gera imediato B-type
EX: compara os registradores
EX: se a condição for verdadeira, PC = PC + imediato
```

Instruções adicionadas:

```text
BNE, BLT, BGE, BLTU, BGEU
```

---

### 5.6 JAL e JALR

`JAL` e `JALR` são instruções de salto com link. Além de alterarem o PC, elas escrevem `PC + 4` em `rd`.

`JAL`:

```text
PC destino = PC + imediato J-type
rd = PC + 4
```

`JALR`:

```text
PC destino = (rs1 + imediato I-type) & ~1
rd = PC + 4
```

---

### 5.7 LUI e AUIPC

`LUI` e `AUIPC` usam imediato U-type.

`LUI`:

```text
rd = imediato_U
```

Na implementação, isso foi feito pela ALU como:

```text
rd = 0 + imediato_U
```

`AUIPC`:

```text
rd = PC + imediato_U
```

---

## 6. Tratamento de hazards

A CPU mantém os mecanismos de tratamento de hazards do pipeline:

| Hazard | Tratamento |
|---|---|
| RAW entre instruções próximas | Forwarding de EX/MEM e MEM/WB para EX. |
| Load-use | Inserção de uma bolha/stall de 1 ciclo. |
| Branch ou jump tomado | Flush das instruções em IF e ID. |

A modificação principal foi no hazard de load-use. Agora o circuito verifica se a instrução em ID realmente usa `rs1` ou `rs2`, evitando travamentos desnecessários em instruções como `LUI`, `AUIPC`, `JAL` e instruções I-type que não usam `rs2`.

---

## 7. Memória e formato little-endian

A memória de dados possui palavras de 32 bits. Para permitir `LB`, `LH`, `LBU`, `LHU`, `SB` e `SH`, a implementação passou a considerar também os bits menos significativos do endereço:

```text
addr[9:2]  -> seleciona a palavra da memória
addr[1:0]  -> seleciona o byte dentro da palavra
```

O formato adotado é **little-endian**:

```text
Offset 0 -> bits [7:0]
Offset 1 -> bits [15:8]
Offset 2 -> bits [23:16]
Offset 3 -> bits [31:24]
```

Exemplo: se uma palavra contém `0xAABBCCDD`, então:

```text
endereço base + 0 -> DD
endereço base + 1 -> CC
endereço base + 2 -> BB
endereço base + 3 -> AA
```

---

## 8. Teste usado para validação

O programa `hello_e2.asm` foi usado para validar as instruções da Etapa 2. Ele testa:

- stores menores: `SB`, `SH`;
- loads com e sem sinal: `LB`, `LH`, `LBU`, `LHU`;
- `LUI` e `AUIPC`;
- branches condicionais: `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`;
- saltos: `JAL`, `JALR`.

Os resultados esperados são gravados na memória de dados:

| Posição | Resultado esperado |
|---|---|
| `dmem[0]` | Resultado de `LB`: `0xFFFFFF95` |
| `dmem[1]` | Resultado de `LBU`: `0x00000095` |
| `dmem[2]` | Resultado de `LH`: `0xFFFFFF95` |
| `dmem[3]` | Resultado de `LHU`: `0x0000FF95` |
| `dmem[4]` | Resultado de `LUI`: `0x00003000` |
| `dmem[5]` | Resultado de `AUIPC`: `0x00000024` |
| `dmem[6]` | Resultado do teste `BNE`: `0x00000001` |
| `dmem[7]` | Resultado do teste `BLT`: `0x00000001` |
| `dmem[8]` | Resultado do teste `BGE`: `0x00000001` |
| `dmem[9]` | Resultado do teste `BLTU`: `0x00000001` |
| `dmem[10]` | Resultado do teste `BGEU`: `0x00000001` |
| `dmem[11]` | Resultado do teste `JAL`: `0x00000001` |
| `dmem[12]` | Resultado do teste `JALR`: `0x00000001` |

Observação: no teste em FPGA usando o primeiro pacote de arquivos modificados, o programa foi validado com o fluxo em que a execução chega ao mecanismo de leitura/dump. Caso o assembly termine com um loop infinito explícito, como `beq x0,x0,0`, a CPU entra nesse loop e não avança para qualquer rotina posterior que dependa da continuação do programa.

---

## 9. Como compilar no Quartus 21.1

1. Abra o projeto no Quartus Prime 21.1.
2. Substitua os arquivos modificados dentro da pasta `src/`.
3. Gere os arquivos `.mif` do programa com o assembler do projeto.
4. Copie os `.mif` gerados para a pasta usada pelo projeto Quartus.
5. Compile o projeto em **Processing → Start Compilation**.
6. Grave o `.sof` na FPGA.

---

## 10. Resumo final das alterações

A implementação expandiu a CPU RV32I pipelined original para executar as instruções solicitadas nas Etapas 1 e 2.

As principais mudanças foram:

- novas operações na ALU;
- nova decodificação de instruções R-type e I-type;
- suporte a loads e stores menores que palavra;
- comparação completa dos branches B-type;
- suporte a `JAL` e `JALR` com escrita de `PC+4`;
- suporte a `LUI` e `AUIPC` com imediato U-type;
- ampliação da geração de imediatos I, S, B, U e J;
- novos sinais de controle no pipeline;
- melhoria na detecção de hazards para evitar stalls falsos.

Com isso, a CPU passou a suportar o conjunto de instruções exigido nas duas etapas, preservando a estrutura de pipeline original e mantendo compatibilidade com o Quartus Prime 21.1.
