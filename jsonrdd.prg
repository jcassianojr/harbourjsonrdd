/*
 * JSONRDD RDD - Motor de Banco de Dados na RAM para arquivos JSON
 * Suporta: JSON Array de Arrays (Ex: [ [1,"A"], [2,"B"] ])
 * Suporta: JSON Array de Hashes (Ex: [ {"id":1, "nome":"A"} ])
 * Inclui: Tipagem Dinâmica e Detecção Automática portadas do FCSVRDD
 */

#include "rddsys.ch"
#include "hbusrrdd.ch"
#include "error.ch"
#include "dbstruct.ch"
#include "dbinfo.ch"

ANNOUNCE JSONRDD

STATIC s_lRetornaTipado := .F. // Define se retorna os dados convertidos (Tipados)
STATIC s_aManualHeader  := {}  // Armazena a matriz de cabeçalho/tipagem passada manualmente
STATIC s_lUseHeader     := .F. // Usa o primeiro item do Array como nome dos campos (se for Array de Array)

// +--------------------------------------------------------------------
// + Funções de Configuração Global
// +--------------------------------------------------------------------


// Função para ativar/desativar a conversão dos dados no GetValue
FUNCTION FJSON_RETORNATIPADO( lUse )
   IF ValType( lUse ) == "L"
      s_lRetornaTipado := lUse
   ENDIF
   RETURN s_lRetornaTipado

// Permite injetar o cabeçalho/estrutura manualmente via matriz (Array)
FUNCTION FJSON_SETCABECALHO( aCabec )
   IF ValType( aCabec ) == "A"
      s_aManualHeader := aCabec
   ENDIF
   RETURN s_aManualHeader

FUNCTION FJSON_USARHEADER( lUse )
   IF ValType( lUse ) == "L"
      s_lUseHeader := lUse
   ENDIF
   RETURN s_lUseHeader


/*
 * Função: JsonParaCsvRdd
 * Objetivo: Converte um arquivo JSON para CSV usando o JSONRDD
 * Parâmetros:
 *   - cFileJson     : Caminho do arquivo JSON de entrada (obrigatório)
 *   - cFileCsv      : Caminho do arquivo CSV de saída (opcional, troca a extensão se vazio)
 *   - lRetornaTipado : Retorna dados tipados (padrão .F.)
 *   - lUserHeader   : Usa o cabeçalho/primeira linha (padrão .F.)
 *   - cDelim        : Delimitador de campos (padrão "|")
 */
FUNCTION JsonParaCsvRdd( cFileJson, cFileCsv, lRetornaTipado, lUserHeader, cDelim )
   LOCAL nHandleCsv, nFld, nI, cLinha
   LOCAL cAliasTemp := "JCN_" + AllTrim( Str( HB_RandomInt( 1000, 9999 ) ) )

   // 1. Validações iniciais
   IF !File( cFileJson )
      ? "Erro: Arquivo JSON nao encontrado -> " + cFileJson
      RETURN .F.
   ENDIF

   // Trata valores padrão caso não sejam passados
   IF ValType( lRetornaTipado ) <> "L"
      lRetornaTipado := .F.
   ENDIF

   IF ValType( lUserHeader ) <> "L"
      lUserHeader := .F.
   ENDIF

   IF ValType( cDelim ) <> "C" .OR. Empty( cDelim )
      cDelim := "|" // Padrão é pipe se não for informado
   ENDIF

   // Define o nome do CSV de saída se não informado
   IF Empty( cFileCsv )
      cFileCsv := hb_FNameExtSet( cFileJson, ".csv" )
   ENDIF

   // 2. Configura as globais do JSONRDD
   FJSON_RETORNATIPADO( lRetornaTipado )
   FJSON_USARHEADER( lUserHeader )

   // 3. Abre o arquivo JSON usando o RDD customizado
   IF !DbUseArea( .T., "JSONRDD", cFileJson, cAliasTemp, .T., .F. )
      ? "Erro ao abrir o arquivo JSON via JSONRDD: " + cFileJson
      RETURN .F.
   ENDIF

   // Cria o arquivo CSV físico em disco
   nHandleCsv := FCreate( cFileCsv )
   IF nHandleCsv == -1
      ? "Erro ao criar arquivo CSV de saida: " + cFileCsv
      ( cAliasTemp )->( DBCloseArea() )
      RETURN .F.
   ENDIF

   ( cAliasTemp )->( DBGoTop() )
   nFld := ( cAliasTemp )->( FCount() )

   // 4. Varre os registros e grava no formato CSV usando o delimitador escolhido
   WHILE ( cAliasTemp )->( !EOF() )
      cLinha := ""
      
      FOR nI := 1 TO nFld
         cLinha += hb_ValToStr( ( cAliasTemp )->( FieldGet( nI ) ) )
         
         IF nI < nFld
            cLinha += cDelim // Usa o delimitador passado por parâmetro (ou "|" por padrão)
         ENDIF
      NEXT

      FWrite( nHandleCsv, cLinha + hb_osNewLine() )
      
      ( cAliasTemp )->( DBSkip() )
   ENDDO

   // 5. Encerramento e limpeza
   FClose( nHandleCsv )
   ( cAliasTemp )->( DBCloseArea() )

   ? "Convertido com sucesso: " + cFileJson + " -> " + cFileCsv + " [Delim: " + cDelim + "]"
RETURN .T.

// +--------------------------------------------------------------------
// + Parser Inteligente para Tipagem
// +--------------------------------------------------------------------
STATIC FUNCTION ParseFieldDefinition( cDef )
   LOCAL aParts, cName := "", cType := "C", nLen := 0, nDec := 0, cSec
   
   cDef := AllTrim( StrTran( cDef, '"', '' ) )
   aParts := hb_ATokens( cDef, "," )
   
   IF Len( aParts ) > 0
      cName := AllTrim( aParts[ 1 ] )
   ENDIF
   
   IF Len( aParts ) > 1
      cSec := Upper( AllTrim( aParts[ 2 ] ) )
      IF cSec $ "N,C,D,L,M"
         cType := cSec
         IF Len( aParts ) > 2
            nLen := Val( aParts[ 3 ] )
         ENDIF
         IF Len( aParts ) > 3
            nDec := Val( aParts[ 4 ] )
         ENDIF
      ELSE
         cType := "N"
         nLen  := Val( cSec )
         IF Len( aParts ) > 2
            nDec := Val( aParts[ 3 ] )
         ENDIF
      ENDIF
   ENDIF
   
   IF cType == "D" .AND. nLen == 0; nLen := 8; ENDIF
   IF cType == "L" .AND. nLen == 0; nLen := 1; ENDIF
   IF cType == "M" .AND. nLen == 0; nLen := 4; ENDIF
   
   RETURN { cName, cType, nLen, nDec }

// +--------------------------------------------------------------------
// + Retorna o Array Auxiliar com a estrutura original tipada do JSON
// +--------------------------------------------------------------------
FUNCTION FJSON_GETSTRUCTORIGINAL()
   LOCAL aWData, aStruct := {}
   
   aWData := USRRDD_AREADATA( Select() )
   IF ValType( aWData ) == "A" .AND. Len( aWData ) >= 5
      aStruct := aWData[ 5 ] // Guarda a estrutura dos campos no JSONRDD
   ENDIF
   
   RETURN aStruct


// +--------------------------------------------------------------------
// + Retorna um Array com os valores dos campos do registro JSON atual
// +--------------------------------------------------------------------
FUNCTION FJSON_GETROW()
   LOCAL aWData, nRecNo, xRecord, aRow := {}, aKeys, nX
   
   aWData := USRRDD_AREADATA( Select() )
   IF ValType( aWData ) == "A" .AND. Len( aWData ) >= 4
      nRecNo := aWData[ 4 ] // Registro atual (índice)
      
      IF nRecNo > 0 .AND. nRecNo <= Len( aWData[ 1 ] )
         xRecord := aWData[ 1 ][ nRecNo ]
         
         // Se for um Objeto / Hash (Chave-Valor)
         IF ValType( xRecord ) == "H"
            aKeys := hb_HKeys( xRecord )
            FOR nX := 1 TO Len( aKeys )
               AAdd( aRow, hb_HGet( xRecord, aKeys[ nX ] ) )
            NEXT
         // Se for um Array de Valores
         ELSEIF ValType( xRecord ) == "A"
            aRow := AClone( xRecord )
         ELSE
            AAdd( aRow, xRecord )
         ENDIF
      ENDIF
   ENDIF
   
   RETURN aRow

// +--------------------------------------------------------------------
// + Retorna o registro atual do JSON em formato de string/linha formatada
// +--------------------------------------------------------------------
FUNCTION FJSON_GETLINE( cDelim )
   LOCAL aWData, nRecNo, xRecord, cLine := "", nX
   
   IF ValType( cDelim ) <> "C" .OR. Empty( cDelim )
      cDelim := "|" // Padrão pipe se não informado
   ENDIF

   aWData := USRRDD_AREADATA( Select() )
   IF ValType( aWData ) == "A" .AND. Len( aWData ) >= 4
      nRecNo := aWData[ 4 ] // Registro atual (índice)
      
      IF nRecNo > 0 .AND. nRecNo <= Len( aWData[ 1 ] )
         xRecord := aWData[ 1 ][ nRecNo ]
         
         // Se for Hash (Objeto), exporta como JSON ou string de valores
         IF ValType( xRecord ) == "H"
            cLine := hb_jsonEncode( xRecord, .F. )
         ELSEIF ValType( xRecord ) == "A"
            // Se for Array, une os valores usando o delimitador escolhido
            FOR nX := 1 TO Len( xRecord )
               cLine += hb_ValToStr( xRecord[ nX ] )
               IF nX < Len( xRecord )
                  cLine += cDelim
               ENDIF
            NEXT
         ELSE
            cLine := hb_ValToStr( xRecord )
         ENDIF
      ENDIF
   ENDIF
   
   RETURN cLine
// +--------------------------------------------------------------------
// + Conversão Lógica Robusta
// +--------------------------------------------------------------------
STATIC FUNCTION StrLogicrdd( cVAL, lDEFAULT )
   IF ValType( lDEFAULT ) <> "L"
      lDEFAULT := .F.
   ENDIF
   cVal := AllTrim( cVal )
   
   SWITCH Upper( cVal )
   CASE ".T."
   CASE "TRUE"
   CASE "YES"
   CASE "SIM"
   CASE "ON"
   CASE "Y"
   CASE "1"
   CASE "T"
   CASE "S"
      RETURN .T.
   CASE ".F."
   CASE "FALSE"
   CASE "NO"
   CASE "NAO"
   CASE "OFF"
   CASE "N"
   CASE "0"
   CASE "F"
   CASE "<NULL>"
   CASE "NULL"
   CASE "NUL"
   CASE "NIL"
      RETURN .F.
   ENDSWITCH

   RETURN lDEFAULT

// +--------------------------------------------------------------------
// + Conversão de Data Inteligente
// +--------------------------------------------------------------------
STATIC FUNCTION StrDateRdd( xData )
   LOCAL dRet := CToD( "" )
   LOCAL cTemp, aParts, cAno, cMes, cDia, nAno

   // 1. Já é data?
   IF ValType( xData ) == "D"
      RETURN xData
   ENDIF

   // 2. É nulo ou inválido?
   IF ValType( xData ) <> "C" .OR. Empty( xData ) .OR. xData == "NULL"
      RETURN dRet
   ENDIF

   xData := AllTrim( xData )

   // 3. Padroniza todos os separadores conhecidos para uma barra "/"
   cTemp := StrTran( xData, "-", "/" )
   cTemp := StrTran( cTemp, ".", "/" )

   // 4. Analisa a estrutura COM os separadores
   aParts := hb_ATokens( cTemp, "/" )

   IF Len( aParts ) == 3
      // TEM SEPARADOR! Identificamos o formato pelo tamanho do primeiro bloco
      IF Len( aParts[ 1 ] ) == 4
         // Formato YYYY/MM/DD (O Ano veio primeiro)
         cAno := aParts[ 1 ]
         cMes := StrZero( Val( aParts[ 2 ] ), 2 ) // Garante 2 dígitos (ex: 3 vira 03)
         cDia := StrZero( Val( aParts[ 3 ] ), 2 )
      ELSE
         // Formato DD/MM/YYYY ou DD/MM/YY (O Dia veio primeiro)
         cDia := StrZero( Val( aParts[ 1 ] ), 2 )
         cMes := StrZero( Val( aParts[ 2 ] ), 2 )
         cAno := aParts[ 3 ]
         
         // Lógica de Século para Anos com 2 dígitos (ex: 05/03/21)
         IF Len( cAno ) == 2
            nAno := Val( cAno )
            IF nAno < 50
               cAno := "20" + cAno
            ELSE
               cAno := "19" + cAno
            ENDIF
         ENDIF
      ENDIF
      
      // Validação contra zeros vazios
      IF cAno + cMes + cDia == "00000000"
         RETURN dRet
      ENDIF
      
      // Converte usando a forma mais veloz do Harbour: SToD("AAAAMMDD")
      RETURN SToD( cAno + cMes + cDia )

   ELSE
      // NÃO TEM SEPARADOR! Veio tudo grudado. Usa a lógica robusta de tamanho
      IF Len( cTemp ) == 8
         // AAAAMMDD ou DDMMAAAA
         IF Val( Left( cTemp, 4 ) ) > 1900
            dRet := SToD( cTemp )
         ELSE
            dRet := SToD( Right( cTemp, 4 ) + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) )
         ENDIF
      ELSEIF Len( cTemp ) == 6
         // DDMMAA (Tudo grudado e ano com 2 dígitos)
         nAno := Val( Right( cTemp, 2 ) )
         IF nAno < 50
            cAno := "20" + Right( cTemp, 2 )
         ELSE
            cAno := "19" + Right( cTemp, 2 )
         ENDIF
         dRet := SToD( cAno + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) )
      ELSE
         // Tenta o CToD nativo como última esperança se a string for muito atípica
         dRet := CToD( xData )
      ENDIF
   ENDIF

   RETURN dRet


// +--------------------------------------------------------------------
// + Métodos Internos do RDD
// +--------------------------------------------------------------------

STATIC FUNCTION FJSON_INIT( nRDD )
   HB_SYMBOL_UNUSED( nRDD )
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_NEW( pWA )
   // aWData MAP: 
   // 1 = Dados (Array Decodificado)
   // 2 = BOF (.L.)
   // 3 = EOF (.L.)
   // 4 = nCurrentRecord (Numérico, índice do array)
   // 5 = Estrutura dos Campos Array Auxiliar
   // 6 = Tipo do Registro JSON ("H" = Hash, "A" = Array)
   
   LOCAL aWData := { {}, .F., .F., 0, {}, "" }
   USRRDD_AREADATA( pWA, aWData )
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_CREATE( nWA, aOpenInfo )
   LOCAL oError := ErrorNew()
   oError:GenCode     := EG_CREATE
   oError:SubCode     := 1004
   oError:Description := hb_langErrMsg( EG_CREATE ) + " (JSONRDD apenas leitura por enquanto)"
   oError:FileName    := aOpenInfo[ UR_OI_NAME ]
   oError:CanDefault  := .T.
   UR_SUPER_ERROR( nWA, oError )
   RETURN HB_FAILURE

STATIC FUNCTION FJSON_OPEN( nWA, aOpenInfo )
   LOCAL cName, aWData, aField, oError, nResult
   LOCAL cJsonText, xJsonData, nI, aKeys, xFirstRow, cType, cParsedName, aParsedDef

   IF aOpenInfo[ UR_OI_ALIAS ] == NIL
      hb_FNameSplit( aOpenInfo[ UR_OI_NAME ], , @cName )
      aOpenInfo[ UR_OI_ALIAS ] := cName
   ENDIF

   IF !File( aOpenInfo[ UR_OI_NAME ] )
      oError := ErrorNew()
      oError:GenCode     := EG_OPEN
      oError:SubCode     := 1001
      oError:Description := hb_langErrMsg( EG_OPEN )
      oError:FileName    := aOpenInfo[ UR_OI_NAME ]
      oError:CanDefault  := .T.
      UR_SUPER_ERROR( nWA, oError )
      RETURN HB_FAILURE
   ENDIF

   // 1. LÊ E DECODIFICA O JSON INTEIRO PARA A MEMÓRIA
   cJsonText := MemoRead( aOpenInfo[ UR_OI_NAME ] )
   xJsonData := hb_jsonDecode( cJsonText )

   IF !( ValType( xJsonData ) == "A" )
      // O RDD espera que o JSON base seja uma Tabela (Array de objetos ou de arrays)
      oError := ErrorNew()
      oError:GenCode     := EG_DATATYPE
      oError:Description := "Formato JSON Invalido. Raiz deve ser um Array []."
      oError:FileName    := aOpenInfo[ UR_OI_NAME ]
      UR_SUPER_ERROR( nWA, oError )
      RETURN HB_FAILURE
   ENDIF

   aWData := USRRDD_AREADATA( nWA )
   
   // Prepara se a primeira linha for Header
   IF s_lUseHeader .AND. Len( xJsonData ) > 0
      xFirstRow := xJsonData[ 1 ]
      hb_ADel( xJsonData, 1, .T. ) // Remove o header dos dados
   ELSEIF Len( xJsonData ) > 0
      xFirstRow := xJsonData[ 1 ]
   ELSE
      xFirstRow := {} // Tabela vazia
   ENDIF

   aWData[ 1 ] := xJsonData
   aWData[ 2 ] := .F.
   aWData[ 3 ] := ( Len( xJsonData ) == 0 )
   aWData[ 4 ] := 1
   aWData[ 5 ] := {} // Estrutura Auxiliar (Guarda as regras Tipadas)
   
   // 2. MONTA A ESTRUTURA DE CAMPOS BASEADO NO TIPO DE JSON
   IF ValType( xFirstRow ) == "H"
      aWData[ 6 ] := "H" // Array de Hashes (Objetos chaves-valores)
      aKeys := hb_HKeys( xFirstRow )
      
      UR_SUPER_SETFIELDEXTENT( nWA, Len( aKeys ) )
      FOR nI := 1 TO Len( aKeys )
         aField := Array( UR_FI_SIZE )
         cParsedName := aKeys[ nI ]
         cType := "C"

         IF Len( s_aManualHeader ) >= nI
            aParsedDef := ParseFieldDefinition( s_aManualHeader[ nI ] )
            cParsedName := aParsedDef[ 1 ]
            cType       := aParsedDef[ 2 ]
         ENDIF

         aField[ UR_FI_NAME ]    := Upper( Left( AllTrim( cParsedName ), 10 ) ) // Nomes padrão DBF (10 chars)
         aField[ UR_FI_TYPE ]    := "C"  // Mantem C seguro no Kernel RDD
         aField[ UR_FI_TYPEEXT ] := 0
         aField[ UR_FI_LEN ]     := 0
         aField[ UR_FI_DEC ]     := 0
         UR_SUPER_ADDFIELD( nWA, aField )
         
         // Auxiliar: { Nome RDD, Chave Original JSON, Tipo Tipado }
         AAdd( aWData[ 5 ], { aField[ UR_FI_NAME ], aKeys[ nI ], cType } )
      NEXT

   ELSEIF ValType( xFirstRow ) == "A"
      aWData[ 6 ] := "A" // Array de Arrays
      
      UR_SUPER_SETFIELDEXTENT( nWA, Len( xFirstRow ) )
      FOR nI := 1 TO Len( xFirstRow )
         aField := Array( UR_FI_SIZE )
         cParsedName := "CAMPO" + AllTrim( Str( nI ) )
         cType := "C"
         
         IF s_lUseHeader .AND. ValType( xFirstRow[ nI ] ) == "C"
            aParsedDef := ParseFieldDefinition( xFirstRow[ nI ] )
            cParsedName := aParsedDef[ 1 ]
            cType       := aParsedDef[ 2 ]
         ELSEIF Len( s_aManualHeader ) >= nI
            aParsedDef := ParseFieldDefinition( s_aManualHeader[ nI ] )
            cParsedName := aParsedDef[ 1 ]
            cType       := aParsedDef[ 2 ]
         ENDIF
         
         aField[ UR_FI_NAME ]    := Upper( Left( AllTrim( cParsedName ), 10 ) )
         aField[ UR_FI_TYPE ]    := "C"
         aField[ UR_FI_TYPEEXT ] := 0
         aField[ UR_FI_LEN ]     := 0
         aField[ UR_FI_DEC ]     := 0
         UR_SUPER_ADDFIELD( nWA, aField )
         
         // Auxiliar: { Nome RDD, Indice Original, Tipo Tipado }
         AAdd( aWData[ 5 ], { aField[ UR_FI_NAME ], nI, cType } )
      NEXT
   ENDIF

   nResult := UR_SUPER_OPEN( nWA, aOpenInfo )

   IF nResult == HB_SUCCESS
      FJSON_GOTOP( nWA )
   ENDIF

   RETURN nResult

STATIC FUNCTION FJSON_CLOSE( nWA )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   
   // Limpa o Array da memória para evitar Memory Leaks
   aWData[ 1 ] := {}
   aWData[ 5 ] := {}
   
   RETURN UR_SUPER_CLOSE( nWA )

// +--------------------------------------------------------------------
// + Extração de Valor do Registro JSON com Tipagem Automática
// +--------------------------------------------------------------------
STATIC FUNCTION FJSON_GETVALUE( nWA, nField, xValue )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   LOCAL xRecord, xRawVal, xRawStr, cType
   LOCAL nRecNo := aWData[ 4 ]

   IF aWData[ 3 ] // EOF
      xValue := ""
      RETURN HB_SUCCESS
   ENDIF

   xRecord := aWData[ 1 ][ nRecNo ] // Pega a linha atual inteira do Array

   // Puxa o dado dependendo do formato do JSON (Hash ou Array)
   IF aWData[ 6 ] == "H"
      IF hb_HHasKey( xRecord, aWData[ 5 ][ nField, 2 ] )
         xRawVal := hb_HGet( xRecord, aWData[ 5 ][ nField, 2 ] )
      ELSE
         xRawVal := ""
      ENDIF
   ELSEIF aWData[ 6 ] == "A"
      IF Len( xRecord ) >= nField
         xRawVal := xRecord[ nField ]
      ELSE
         xRawVal := ""
      ENDIF
   ENDIF

   // Prepara uma versão em String do dado puro capturado para ser convertida sem falhas
   xRawStr := hb_ValToStr( xRawVal )

   // >>> APLICAÇÃO DA REGRA DE RETORNO CONVERTIDO (TIPADO) SE ATIVO <<<
   IF s_lRetornaTipado .AND. Len( aWData[ 5 ] ) >= nField
      cType := aWData[ 5 ][ nField ][ 3 ] // Pega o tipo (N, C, D, L, M) da matriz auxiliar
      
      DO CASE
         CASE cType == "N"
            xValue := Val( xRawStr )
         CASE cType == "D"
            xValue := StrDateRdd( xRawStr )
         CASE cType == "L"
            xValue := StrLogicrdd( xRawStr, .F. )
         OTHERWISE
            xValue := xRawStr 
      ENDCASE
   ELSE
      // Comportamento normal do RDD: Retorna bruto
      xValue := xRawStr
   ENDIF

   RETURN HB_SUCCESS

// +--------------------------------------------------------------------
// + Navegação Pura em RAM (Velocidade Extrema)
// +--------------------------------------------------------------------
STATIC FUNCTION FJSON_GOTOP( nWA )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   
   IF Len( aWData[ 1 ] ) == 0
      aWData[ 2 ] := .T.
      aWData[ 3 ] := .T.
      aWData[ 4 ] := 0
   ELSE
      aWData[ 2 ] := .T.
      aWData[ 3 ] := .F.
      aWData[ 4 ] := 1
   ENDIF
   
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_GOBOTTOM( nWA )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   LOCAL nLen := Len( aWData[ 1 ] )
   
   IF nLen == 0
      aWData[ 2 ] := .T.
      aWData[ 3 ] := .T.
      aWData[ 4 ] := 0
   ELSE
      aWData[ 2 ] := .F.
      aWData[ 3 ] := .F.
      aWData[ 4 ] := nLen
   ENDIF
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_SKIPRAW( nWA, nRecords )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   LOCAL nLen   := Len( aWData[ 1 ] )
   LOCAL nNewRec

   IF nRecords == 0
      RETURN HB_SUCCESS
   ENDIF

   nNewRec := aWData[ 4 ] + nRecords

   IF nNewRec > nLen
      aWData[ 4 ] := nLen + 1
      aWData[ 3 ] := .T. // EOF
      aWData[ 2 ] := .F.
   ELSEIF nNewRec < 1
      aWData[ 4 ] := 1
      aWData[ 3 ] := .F.
      aWData[ 2 ] := .T. // BOF
   ELSE
      aWData[ 4 ] := nNewRec
      aWData[ 3 ] := .F.
      aWData[ 2 ] := ( nNewRec == 1 )
   ENDIF

   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_GOTO( nWA, nRecord )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   
   IF nRecord <= 1
      FJSON_GOTOP( nWA )
   ELSEIF nRecord > Len( aWData[ 1 ] )
      aWData[ 4 ] := Len( aWData[ 1 ] ) + 1
      aWData[ 3 ] := .T. // EOF
   ELSE
      aWData[ 4 ] := nRecord
      aWData[ 2 ] := .F.
      aWData[ 3 ] := .F.
   ENDIF
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_GOTOID( nWA, nRecord )
   RETURN FJSON_GOTO( nWA, nRecord )

STATIC FUNCTION FJSON_Bof( nWA, lBof )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   lBof := aWData[ 2 ]
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_EOF( nWA, lEof )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   lEof := aWData[ 3 ]
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_DELETED( nWA, lDeleted )
   HB_SYMBOL_UNUSED( nWA )
   lDeleted := .F. // JSON não tem registro "Deletado" natural
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_RECID( nWA, nRecNo )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   nRecNo := aWData[ 4 ]
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_RECCOUNT( nWA, nRecords )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   nRecords := Len( aWData[ 1 ] )
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_FCOUNT( nWA, nFields )
   LOCAL aWData := USRRDD_AREADATA( nWA )
   nFields := Len( aWData[ 5 ] )
   RETURN HB_SUCCESS

STATIC FUNCTION FJSON_RDDINFO( nIndex, cargo ) 
   Local xRet := NIL
   HB_SYMBOL_UNUSED( cargo )

   DO CASE
      CASE nIndex == RDDI_TABLEEXT
         xRet := ".json"
      CASE nIndex == RDDI_MEMOEXT
         xRet := ""
      CASE nIndex == RDDI_ORDBAGEXT
         xRet := ""
   ENDCASE
RETURN xRet

STATIC FUNCTION FJSON_INFO( nWA, nItem, xArg )
   LOCAL xRet := NIL

   DO CASE
      CASE nItem == DBI_ISDBF
         xRet := .F.
      CASE nItem == DBI_CANPUTREC
         xRet := .F.
      OTHERWISE
         xRet := UR_SUPER_INFO( nWA, nItem, xArg )
   ENDCASE
RETURN xRet

FUNCTION JSONRDD_GETFUNCTABLE( pFuncCount, pFuncTable, pSuperTable, nRddID )
   LOCAL cSuperRDD := NIL
   LOCAL aMyFunc[ UR_METHODCOUNT ]

   aMyFunc[ UR_INIT ]       := @FJSON_INIT()
   aMyFunc[ UR_NEW ]        := @FJSON_NEW()
   aMyFunc[ UR_CREATE ]     := @FJSON_CREATE()
   aMyFunc[ UR_OPEN ]       := @FJSON_OPEN()
   aMyFunc[ UR_CLOSE ]      := @FJSON_CLOSE()
   aMyFunc[ UR_BOF  ]       := @FJSON_Bof()
   aMyFunc[ UR_EOF  ]       := @FJSON_Eof()
   aMyFunc[ UR_DELETED ]    := @FJSON_DELETED()
   aMyFunc[ UR_SKIPRAW ]    := @FJSON_SKIPRAW()
   aMyFunc[ UR_GOTO ]       := @FJSON_GOTO()
   aMyFunc[ UR_GOTOID ]     := @FJSON_GOTOID()
   aMyFunc[ UR_GOTOP ]      := @FJSON_GOTOP()
   aMyFunc[ UR_GOBOTTOM ]   := @FJSON_GOBOTTOM()
   aMyFunc[ UR_RECID ]      := @FJSON_RECID()
   aMyFunc[ UR_RECCOUNT ]   := @FJSON_RECCOUNT()
   aMyFunc[ UR_GETVALUE ]   := @FJSON_GETVALUE()
   aMyFunc[ UR_FIELDCOUNT ] := @FJSON_FCOUNT()
   aMyFunc[ UR_RDDINFO ]    := @FJSON_RDDINFO()
   aMyFunc[ UR_INFO ]       := @FJSON_INFO()

   RETURN USRRDD_GETFUNCTABLE( pFuncCount, pFuncTable, pSuperTable, nRddID, ;
      cSuperRDD, aMyFunc )

INIT PROCEDURE JSONRDD_INIT()
   rddRegister( "JSONRDD", RDT_FULL )
   RETURN