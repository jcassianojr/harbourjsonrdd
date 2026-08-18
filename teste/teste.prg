/*
 * Programa de Teste: Utilizando o JSONRDD para ler arquivos JSON como tabelas
 * Linguagem: Harbour
 */

REQUEST JSONRDD
REQUEST HB_CODEPAGE_PTISO

PROCEDURE Main()
   LOCAL aListaArq, nFimArq, kk
   LOCAL cArqJson, cArqCsv

   // Configurações de ambiente
   hb_idleState()
   Set( _SET_CODEPAGE, "PTISO" )
   SetMode( 25, 80 )
   cls

   ? "Iniciando conversao em lote de JSON para CSV via JSONRDD..."
   ? "--------------------------------------------------"

   // 1. Localiza todos os arquivos com extensão .json na pasta atual
   aListaArq := Directory( "*.json", "D" )
   nFimArq   := Len( aListaArq )

   IF nFimArq == 0
      ? "Nenhum arquivo .json encontrado no diretorio."
      RETURN
   ENDIF

   // 2. Loop para processar cada arquivo encontrado
   FOR kk := 1 TO nFimArq
      cArqJson := Lower( aListaArq[ kk, 1 ] )
      cArqCsv  := hb_FNameExtSet( cArqJson, ".csv" )

      ? "Processando arquivo: " + cArqJson

      // Chama a função de conversão passando os parâmetros (lRetornaTipado=.F., lUserHeader=.F. por padrão)
      IF JsonParaCsvRdd( cArqJson, cArqCsv, .F., .F. )
         ? "   -> Sucesso: Gerado " + cArqCsv
      ELSE
         ? "   -> Erro ao converter o arquivo: " + cArqJson
      ENDIF
   NEXT kk

   ? "--------------------------------------------------"
   ? "Processo em lote concluido com sucesso!"
   
RETURN


PROCEDURE Main03()
   // Exemplo 1: Conversão básica (parâmetros tipado e header assumem falso por padrão)
   JsonParaCsvRdd( "sefazmodfrete.json" )

   // Exemplo 2: Conversão informando explicitamente os parâmetros
   JsonParaCsvRdd( "sefazcorrecao.json", "sefazcorrecao.csv", .F., .F. )
RETURN

PROCEDURE Main02()
   LOCAL aListaArq, nFimArq, kk
   LOCAL cArqJson, cArqCsv, nHandleCsv, nFld, nI, cLinha

   hb_idleState()
   Set( _SET_CODEPAGE, "PTISO" )
   SetMode( 25, 80 )
   cls

   ? "Iniciando conversao de JSON para CSV usando o JSONRDD..."
   ? "--------------------------------------------------"

   // 1. Procura por todos os arquivos .json no diretório atual
   aListaArq := Directory( "*.json", "D" )
   nFimArq   := Len( aListaArq )

   IF nFimArq == 0
      ? "Nenhum arquivo .json encontrado no diretorio atual."
      RETURN
   ENDIF

   // 2. Configurações globais opcionais do JSONRDD
   FJSON_RETORNATIPADO( .F. ) // Força o retorno em formato string limpo para exportação
   FJSON_USARHEADER( .F. )

   FOR kk := 1 TO nFimArq
      cArqJson := Lower( aListaArq[ kk, 1 ] )
      cArqCsv  := hb_FNameExtSet( cArqJson, ".csv" )

      ? "Processando via JSONRDD: " + cArqJson + " -> " + cArqCsv

      // 3. Abre o JSON usando o driver JSONRDD
      IF !DbUseArea( .T., "JSONRDD", cArqJson, "TMPJSON", .T., .F. )
         ? "   [ERRO] Nao foi possivel abrir o arquivo: " + cArqJson
         LOOP
      ENDIF

      // Cria o arquivo CSV de saída
      nHandleCsv := FCreate( cArqCsv )
      IF nHandleCsv == -1
         ? "   [ERRO] Nao foi possivel criar o arquivo CSV: " + cArqCsv
         DBCloseArea()
         LOOP
      ENDIF

      nFld := FCount() // Total de colunas identificadas pelo RDD

      // 4. Varre os registros da "tabela" JSON com a velocidade de RAM do RDD
      TMPJSON->( DBGoTop() )
      
      WHILE TMPJSON->( !EOF() )
         cLinha := ""
         
         FOR nI := 1 TO nFld
            // Obtém o valor de cada campo dinamicamente por índice
            cLinha += hb_ValToStr( TMPJSON->( FieldGet( nI ) ) )
            
            // Adiciona o delimitador pipe entre as colunas (exceto na última)
            IF nI < nFld
               cLinha += "|"
            ENDIF
         NEXT

         // Escreve a linha formatada no arquivo CSV com quebra de linha do S.O.
         FWrite( nHandleCsv, cLinha + hb_osNewLine() )
         
         TMPJSON->( DBSkip() )
      ENDDO

      FClose( nHandleCsv )
      TMPJSON->( DBCloseArea() )
      
      ? "   [SUCESSO] Gerado: " + cArqCsv
   NEXT kk

   ? "--------------------------------------------------"
   ? "Processo de exportacao em massa concluido com sucesso!"
   
RETURN

PROCEDURE Main01()
   LOCAL cArquivoJson := "sefazmodfrete.json" // Exemplo de arquivo JSON compatível
   
   hb_idleState()
   Set( _SET_CODEPAGE, "PTISO" )
   SetMode( 25, 80 )
   cls

   ? "Testando o novo JSONRDD..."
   ? "--------------------------------------------------"

   IF !File( cArquivoJson )
      ? "Arquivo nao encontrado: " + cArquivoJson
      ? "Certifique-se de que o arquivo JSON esta na pasta."
      RETURN
   ENDIF

   // 1. Configurações opcionais do RDD (Ativa a tipagem se desejar)
   FJSON_RETORNATIPADO( .T. ) 
   FJSON_USARHEADER( .F. )    // Como é array de array puro, não usa header automático na 1ª linha

   // 2. Abre o arquivo JSON usando o novo RDD
   IF !DbUseArea( .T., "JSONRDD", cArquivoJson, "MODFRETE", .T., .F. )
      ? "Erro ao abrir o arquivo JSON com o JSONRDD."
      RETURN
   ENDIF

   ? "Arquivo aberto com sucesso! Alias: MODFRETE"
   ? "Total de Registros (RecCount):", RecCount()
   ? "Total de Campos (FCount):", FCount()
   ? "--------------------------------------------------"

   // 3. Navegação pelos registros igualzinho a uma tabela DBF
   DBGoTop()
   
   WHILE !EOF()
      // Como o arquivo sefazmodfrete.json é um array de arrays [código, descrição],
      // podemos ler os campos ordenadamente:
      ? "Codigo:", FIELDGET( 1 ), "-> Descricao:", FIELDGET( 2 )
      
      DBSkip()
   ENDDO

   ? "--------------------------------------------------"
   ? "Fim do arquivo alcançado (EOF)."

   // Fecha a área de trabalho
   DBCloseArea()

RETURN