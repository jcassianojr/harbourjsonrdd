```markdown
# JSONRDD 🚀

O **JSONRDD** é um driver RDD (Replaceable Database Driver) customizado para o ecossistema **Harbour**, projetado para permitir a leitura e manipulação nativa de arquivos **JSON** como se fossem tabelas de banco de dados tradicionais (DBF), utilizando os comandos padrão de navegação e manipulação de áreas (`USE`, `DBGoTop()`, `DBSkip()`, `FIELDGET()`, etc.).

Com o **JSONRDD**, você elimina a necessidade de fazer parsers manuais ou conversões complexas em disco antes de consultar estruturas de dados dinâmicas.

---

## 🌟 Principais Funcionalidades

* **Abertura Direta**: Leia arquivos `.json` diretamente em uma Work Area do Harbour.
* **Suporte a Múltiplos Formatos JSON**:
  * *Array de Arrays* (Ex: `[[1, "Item A"], [2, "Item B"]]`)[cite: 7].
  * *Array de Hashes / Objetos* (Ex: `[{"codigo": 1, "descricao": "Item A"}]`).
* **Velocidade em Memória**: O arquivo JSON é decodificado inteiramente para a RAM, tornando as operações de salto (`SKIP`, `GOTO`) e contagem instantâneas.
* **Tipagem Inteligente**: Herda as rotinas avançadas de conversão de tipos (Datas e Lógicos) integradas.
* **Paridade com FCSVRDD**: Mantém compatibilidade conceitual e estrutural com os motores de arquivos texto e CSV já utilizados.

---

## 📦 Instalação e Requisitos

Basta incluir o arquivo `JSONRDD.prg` no seu projeto junto com os demais módulos do Harbour e registrar o driver utilizando a macro de anúncio:

```clipper
REQUEST JSONRDD

```

---

## ⚙️ Funções de Configuração Global

Antes ou durante a abertura das tabelas JSON, você pode ajustar o comportamento do driver através das seguintes funções auxiliares:

| Função | Parâmetro | Descrição |
| --- | --- | --- |
| `FJSON_RETORNATIPADO( lVal )` | `.T.` / `.F.` | Ativa ou desativa o retorno de dados já tipados (Data, Numérico, Lógico). Padrão é `.F.` (retorna string crua). |
| `FJSON_USARHEADER( lVal )` | `.T.` / `.F.` | Define se a primeira linha/objeto do JSON deve ser tratada como o cabeçalho (nomes de campos). |
| `FJSON_SETCABECALHO( aCabec )` | `Array` | Injeta uma estrutura de campos customizada manualmente. |

---

## 🚀 Exemplo de Uso Básico

O exemplo abaixo demonstra como abrir um arquivo JSON estruturado e navegar por seus registros utilizando comandos padrão do Harbour:

```clipper
REQUEST JSONRDD
REQUEST HB_CODEPAGE_PTISO

PROCEDURE Main()
   hb_idleState()
   Set( _SET_CODEPAGE, "PTISO" )

   // Ativa opcionalmente o retorno tipado
   FJSON_RETORNATIPADO( .T. ) 

   // Abre o arquivo JSON usando o JSONRDD
   IF DbUseArea( .T., "JSONRDD", "tabela_exemplo.json", "MEUALIAS", .T., .F. )
      
      ? "Total de Registros:", RecCount()
      ? "Total de Campos:", FCount()
      ? "--------------------------------------------------"

      DBGoTop()
      WHILE !EOF()
         // Lê os campos de forma sequencial ou nominal
         ? FIELDGET(1), "->", FIELDGET(2)
         DBSkip()
      ENDDO

      DBCloseArea()
   ELSE
      ? "Erro ao abrir o arquivo JSON."
   ENDIF

RETURN

```

---

## 🔄 Exemplo de Conversão em Lote (JSON para CSV)

Você também pode utilizar o motor do RDD para automatizar a conversão de múltiplos arquivos JSON contidos em um diretório para o formato CSV delimitado por pipe (`|`):

```clipper
FUNCTION JsonParaCsvRdd( cFileJson, cFileCsv, lRetornaTipado, lUserHeader )
   LOCAL nHandleCsv, nFld, nI, cLinha
   LOCAL cAliasTemp := "JCN_" + AllTrim( Str( HB_RandomInt( 1000, 9999 ) ) )

   IF !File( cFileJson )
      RETURN .F.
   ENDIF

   DEFAULT lRetornaTipado TO .F.
   DEFAULT lUserHeader    TO .F.
   DEFAULT cFileCsv       TO hb_FNameExtSet( cFileJson, ".csv" )

   FJSON_RETORNATIPADO( lRetornaTipado )
   FJSON_USARHEADER( lUserHeader )

   IF !DbUseArea( .T., "JSONRDD", cFileJson, cAliasTemp, .T., .F. )
      RETURN .F.
   ENDIF

   nHandleCsv := FCreate( cFileCsv )
   IF nHandleCsv == -1
      ( cAliasTemp )->( DBCloseArea() )
      RETURN .F.
   ENDIF

   ( cAliasTemp )->( DBGoTop() )
   nFld := ( cAliasTemp )->( FCount() )

   WHILE ( cAliasTemp )->( !EOF() )
      cLinha := ""
      FOR nI := 1 TO nFld
         cLinha += hb_ValToStr( ( cAliasTemp )->( FieldGet( nI ) ) )
         IF nI < nFld
            cLinha += "|" // Delimitador Pipe
         ENDIF
      NEXT
      FWrite( nHandleCsv, cLinha + hb_osNewLine() )
      ( cAliasTemp )->( DBSkip() )
   ENDDO

   FClose( nHandleCsv )
   ( cAliasTemp )->( DBCloseArea() )

RETURN .T.

```

---

## 🛠️ Contribuindo

Contribuições, sugestões de melhorias e relatórios de bugs são sempre bem-vindos! Sinta-se à vontade para abrir uma *Issue* ou enviar um *Pull Request*.

---

## 📄 Licença

Este projeto é distribuído sob os termos da licença MIT.

```

```