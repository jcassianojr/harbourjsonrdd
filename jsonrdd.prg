/*
 * JSONRDD RDD - Motor de Banco de Dados na RAM para arquivos JSON
 * Suporta: JSON Array de Arrays e JSON Array de Hashes
 * Atualização: Proteção contra OOM em CSV, ArrayToLine, Proteção Numérica e Fallback Híbrido.
 */

#include "rddsys.ch"
#include "hbusrrdd.ch"
#include "error.ch"
#include "dbstruct.ch"
#include "dbinfo.ch"

ANNOUNCE JSONRDD

STATIC s_lRetornaTipado  := .F. // Define se retorna os dados convertidos (Tipados)
STATIC s_aManualHeader   := {}  // Armazena a matriz de cabeçalho/tipagem passada manualmente
STATIC s_lUseHeader      := .F. // Usa o primeiro item do Array como nome dos campos (se for Array de Array)
STATIC s_lStoreLargeNums := .F. // Trata números longos (>15 chars) como string

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

// Nova configuração: Proteção de precisão em IDS longos
FUNCTION FJSON_STORELARGENUMS( lUse )
   IF ValType( lUse ) == "L"
      s_lStoreLargeNums := lUse
   ENDIF
   RETURN s_lStoreLargeNums

/*
 * Função: JsonParaCsvRdd
 * Objetivo: Converte um arquivo JSON para CSV usando o JSONRDD
 */
FUNCTION JsonParaCsvRdd( cFileJson, cFileCsv, lRetornaTipado, lUserHeader, cDelim )
   LOCAL nHandleCsv, nFld, nI, cLinha, aBuffer, cBlocoEscrita := ""
   LOCAL cAliasTemp := "JCN_" + AllTrim( Str( HB_RandomInt( 1000, 9999 ) ) )
   LOCAL nLinhasCache := 0

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

   // 4. Varre os registros e grava no formato CSV usando buffer
   WHILE ( cAliasTemp )->( !EOF() )
      aBuffer := Array( nFld )
      
      FOR nI := 1 TO nFld
         aBuffer[ nI ] := hb_ValToStr( ( cAliasTemp )->( FieldGet( nI ) ) )
      NEXT

      cBlocoEscrita += hb_ArrayToLine( aBuffer, cDelim ) + hb_osNewLine()
      nLinhasCache++

      // Descarrega no disco para evitar consumo massivo de RAM
      IF nLinhasCache > 1000
         FWrite( nHandleCsv, cBlocoEscrita )
         cBlocoEscrita := ""
         nLinhasCache := 0
      ENDIF
      
      ( cAliasTemp )->( DBSkip() )
   ENDDO

   // Grava o resíduo
   IF !Empty( cBlocoEscrita )
      FWrite( nHandleCsv, cBlocoEscrita )
   ENDIF

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
   LOCAL aWData, nRecNo, xRecord, cLine := "", nX, aBuffer
   
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
            aBuffer := Array( Len( xRecord ) )
            FOR nX := 1 TO Len( xRecord )
               aBuffer[ nX ] := hb_ValToStr( xRecord[ nX ] )
            NEXT
            cLine := hb_ArrayToLine( aBuffer, cDelim )
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
// +    Static Function StrDateRdd( xData )
// +    Conversor inteligente de datas universal para o RDD ADO
// +--------------------------------------------------------------------
STATIC FUNCTION StrDateRdd( xData )
LOCAL dRet := CToD( "" )
   LOCAL cTemp, aParts 
   LOCAL i, nMes, cMes, cAno, cDia, nDia, nAno, cMesStr
   LOCAL cCleanData
   
   // Matrizes independentes pela clareza e velocidade nativa do AScan
   LOCAL aMonthsEN := { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
   LOCAL aMonthsPT := { "JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ" }

   IF ValType( xData ) == "D"
      RETURN xData
   ENDIF

   IF ValType( xData ) <> "C" .OR. Empty( xData )
      RETURN dRet
   ENDIF
   
   // Limpa uma única vez para otimizar os testes
   cCleanData := Upper( AllTrim( xData ) )

   // Barreira imediata contra literais nulos/vazios
   IF cCleanData == "NULL" .OR. cCleanData == "NIL" .OR. cCleanData == "<NULL>" .OR. cCleanData == "NUL" .OR. cCleanData == "/  /" .OR. cCleanData == "-  -"
      RETURN dRet
   ENDIF

   cTemp := AllTrim( xData )

   // -------------------------------------------------------------------------
   // Suporte a Formatos HTTP-date e Logs (Inglês e Português)
   // -------------------------------------------------------------------------
   cTemp := StrTran( cTemp, ",", " " )
   cTemp := StrTran( cTemp, "-", " " )

   DO WHILE "  " $ cTemp
      cTemp := StrTran( cTemp, "  ", " " )
   ENDDO

   aParts := hb_ATokens( AllTrim( cTemp ), " " )

   IF Len( aParts ) >= 4
      FOR i := 1 TO Len( aParts )
         cMesStr := Upper( Left( aParts[ i ], 3 ) )
         
         // 1. Busca primeiro em Inglês
         nMes := AScan( aMonthsEN, cMesStr )
         
         // 2. Se não encontrar, tenta em Português
         IF nMes == 0
            nMes := AScan( aMonthsPT, cMesStr )
         ENDIF
         
         // Se encontrou o mês, processa
         IF nMes > 0
            cMes := StrZero( nMes, 2 )
            
            // Extrai o Dia e o Ano baseado na posição do Mês (ANSI C vs RFC)
            IF i == 2 .AND. Len( aParts ) >= 5 // ANSI C asctime
               cDia := StrZero( Val( aParts[ 3 ] ), 2 )
               cAno := aParts[ 5 ]
            ELSEIF i == 3 // RFC 1123 / RFC 850
               cDia := StrZero( Val( aParts[ 2 ] ), 2 )
               cAno := aParts[ 4 ]
               
               IF Len( cAno ) == 2
                  nAno := Val( cAno )
                  cAno := iif( nAno < 50, "20" + cAno, "19" + cAno )
               ENDIF
            ELSE
               LOOP 
            ENDIF
            
            nDia := Val( cDia )
            nAno := Val( cAno )
            
            IF nDia >= 1 .AND. nDia <= 31 .AND. nAno >= 1000 .AND. Len( cAno ) == 4
               dRet := SToD( cAno + cMes + cDia )
               IF !Empty( dRet )
                  RETURN dRet
               ENDIF
            ENDIF
         ENDIF
      NEXT
   ENDIF

   // -------------------------------------------------------------------------
   // Fallback Original para Bancos de Dados (YYYY-MM-DD, DD/MM/YYYY, etc.)
   // -------------------------------------------------------------------------
   cTemp := AllTrim( xData ) // Restaura a string original limpa para o fallback
   cTemp := StrTran( cTemp, "-", "/" ) 
   cTemp := StrTran( cTemp, ".", "/" ) 
   aParts := hb_ATokens( cTemp, "/" ) 

   IF Len( aParts ) == 3
      IF Len( aParts[ 1 ] ) == 4
         cAno := aParts[ 1 ]
         cMes := StrZero( Val( aParts[ 2 ] ), 2 ) 
         cDia := StrZero( Val( aParts[ 3 ] ), 2 )
      ELSE
         cDia := StrZero( Val( aParts[ 1 ] ), 2 ) 
         cMes := StrZero( Val( aParts[ 2 ] ), 2 )
         cAno := aParts[ 3 ]
         IF Len( cAno ) == 2
            nAno := Val( cAno )
            cAno := iif( nAno < 50, "20" + cAno, "19" + cAno ) 
         ENDIF
      ENDIF
      IF cAno + cMes + cDia == "00000000"
         RETURN CToD( "" )
      ENDIF 
      dRet := SToD( cAno + cMes + cDia ) 
      RETURN iif( Empty( dRet ), CToD( "" ), dRet )
   ELSE
      IF Len( cTemp ) == 8
         IF Val( Left( cTemp, 4 ) ) > 1900
            dRet := SToD( cTemp ) 
         ELSE
            dRet := SToD( Right( cTemp, 4 ) + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) 
         ENDIF
      ELSEIF Len( cTemp ) == 6
         nAno := Val( Right( cTemp, 2 ) )
         cAno := iif( nAno < 50, "20" + Right( cTemp, 2 ), "19" + Right( cTemp, 2 ) ) 
         dRet := SToD( cAno + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) 
      ELSE
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

   // 2. SLOW PATH: Motor tolerante para JSON fora de formato estrito
   IF ValType( xJsonData ) <> "A" .AND. !Empty( cJsonText )
      xJsonData := RelaxedJsonDecode( cJsonText )
   ENDIF

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
         cParsedName := "CAMPO" + AllTrim( StrZERO( nI,3 ) )
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
            IF s_lStoreLargeNums .AND. Len( AllTrim( xRawStr ) ) >= 16
               xValue := xRawStr
            ELSE
               xValue := Val( xRawStr )
            ENDIF
         CASE cType == "D"
            xValue := StrDateRdd( xRawStr )
         CASE cType == "T" .OR. cType == "@"
            xValue := UniversalDateTime( xRawStr ) // <-- INJEÇÃO: Conversor Universal de Data e Hora      
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
   
// +--------------------------------------------------------------------
// +  Função: UniversalDateTime
// +  Objetivo: Tratar datas complexas mantendo e corrigindo o horário
// +  Retorna: Timestamp nativo (T) de alta precisão
// +--------------------------------------------------------------------
STATIC FUNCTION UniversalDateTime( xData )

   LOCAL cStr, cDataLimpa, aParts, i, dData
   LOCAL cTime := "00:00:00"
   LOCAL nHour := 0, nMin := 0, nSec := 0

   // 1. Já é Data ou Timestamp? Trata a conversão direta
   IF ValType( xData ) == "T"
      RETURN xData
   ELSEIF ValType( xData ) == "D"
      RETURN hb_DateTime( Year(xData), Month(xData), Day(xData) )
   ENDIF

   // 2. Barreira para nulos ou variáveis não suportadas
   IF ValType( xData ) <> "C" .OR. Empty( xData )
      RETURN hb_DateTime( 0, 0, 0 )
   ENDIF

   // 3. Limpa espaços e conserta erros como ";" ou tags ISO "T"
   cStr := AllTrim( xData )
   cStr := StrTran( cStr, ";", ":" )
   cStr := StrTran( cStr, "T", " " )

   aParts := hb_ATokens( cStr, " " )
   cDataLimpa := ""

   // 4. Caçador de Horários
   FOR i := 1 TO Len( aParts )
      IF ":" $ aParts[i] .AND. Val( StrTran( aParts[i], ":", "" ) ) >= 0
         cTime := aParts[i] // Isola apenas a hora encontrada
      ELSE
         cDataLimpa += aParts[i] + " " // Reconstrói string base só da data
      ENDIF
   NEXT

   cDataLimpa := AllTrim( cDataLimpa )
   
   // 5. Utiliza o motor otimizado para extrair o calendário válido
   dData := StrDateRdd( cDataLimpa )

   // Fallback se a rotina retornar vazio, checa direto via Harbour CToD
   IF Empty( dData ) .AND. !Empty( CToD( cDataLimpa ) )
      dData := CToD( cDataLimpa )
   ENDIF

   IF Empty( dData )
      RETURN hb_DateTime( 0, 0, 0 )
   ENDIF

   // 6. Separa e converte as partes do Horário
   aParts := hb_ATokens( cTime, ":" )
   IF Len( aParts ) >= 1
      nHour := Val( aParts[1] )
   ENDIF
   IF Len( aParts ) >= 2
      nMin  := Val( aParts[2] )
   ENDIF
   IF Len( aParts ) >= 3
      nSec  := Val( aParts[3] )
   ENDIF

   // 7. Retorna o Objeto Timestamp Oficial
   RETURN hb_DateTime( Year( dData ), Month( dData ), Day( dData ), nHour, nMin, nSec ) 


// +--------------------------------------------------------------------
// + Interpretador JSON Tolerante (Fallback Híbrido)
// + Suporta chaves sem aspas e strings com aspas simples
// +--------------------------------------------------------------------
STATIC FUNCTION RelaxedJsonDecode( cJson )
   LOCAL nIndex := 1
   LOCAL cChar, xResult := NIL

   RelaxedIgnoreSpaces( cJson, @nIndex )
   cChar := SubStr( cJson, nIndex, 1 )
   
   IF cChar == "["
      xResult := RelaxedParseArray( cJson, @nIndex )
   ELSEIF cChar == "{"
      xResult := RelaxedParseObject( cJson, @nIndex )
   ENDIF
   
   RETURN xResult

STATIC FUNCTION RelaxedParseArray( cJson, nIndex )
   LOCAL aList := {}, xValue
   
   nIndex++ 
   RelaxedIgnoreSpaces( cJson, @nIndex )
   
   WHILE nIndex <= Len( cJson ) .AND. SubStr( cJson, nIndex, 1 ) != "]"
      xValue := RelaxedParseValue( cJson, @nIndex )
      AAdd( aList, xValue )
      
      RelaxedIgnoreSpaces( cJson, @nIndex )
      IF SubStr( cJson, nIndex, 1 ) == ","
         nIndex++ 
         RelaxedIgnoreSpaces( cJson, @nIndex )
      ENDIF
   ENDDO
   
   nIndex++ 
   RETURN aList

STATIC FUNCTION RelaxedParseObject( cJson, nIndex )
   LOCAL hObj := {=>}, cKey, xValue, cChar
   
   nIndex++ 
   RelaxedIgnoreSpaces( cJson, @nIndex )
   
   WHILE nIndex <= Len( cJson ) .AND. SubStr( cJson, nIndex, 1 ) != "}"
      cKey := RelaxedParseKey( cJson, @nIndex )
      RelaxedIgnoreSpaces( cJson, @nIndex )
      
      IF SubStr( cJson, nIndex, 1 ) == ":"
         nIndex++
      ENDIF
      
      RelaxedIgnoreSpaces( cJson, @nIndex )
      
      xValue := RelaxedParseValue( cJson, @nIndex )
      hb_HSet( hObj, cKey, xValue )
      
      RelaxedIgnoreSpaces( cJson, @nIndex )
      IF SubStr( cJson, nIndex, 1 ) == ","
         nIndex++
         RelaxedIgnoreSpaces( cJson, @nIndex )
      ENDIF
   ENDDO
   
   nIndex++ 
   RETURN hObj

STATIC FUNCTION RelaxedParseValue( cJson, nIndex )
   LOCAL cChar := SubStr( cJson, nIndex, 1 ), xVal
   
   DO CASE
      CASE cChar == "{"
         xVal := RelaxedParseObject( cJson, @nIndex )
      CASE cChar == "["
         xVal := RelaxedParseArray( cJson, @nIndex )
      CASE cChar == '"' .OR. cChar == "'"
         xVal := RelaxedParseString( cJson, @nIndex, cChar )
      CASE IsDigit( cChar ) .OR. cChar == "-"
         xVal := RelaxedParseNumber( cJson, @nIndex )
      OTHERWISE
         xVal := RelaxedParseLiteral( cJson, @nIndex )
   ENDCASE
   
   RETURN xVal

STATIC PROCEDURE RelaxedIgnoreSpaces( cJson, nIndex )
   WHILE nIndex <= Len( cJson ) .AND. SubStr( cJson, nIndex, 1 ) $ " " + hb_osNewLine() + Chr(9)
      nIndex++
   ENDDO
   RETURN

STATIC FUNCTION RelaxedParseKey( cJson, nIndex )
   LOCAL cKey := "", cChar := SubStr( cJson, nIndex, 1 )
   IF cChar == '"' .OR. cChar == "'"
      cKey := RelaxedParseString( cJson, @nIndex, cChar )
   ELSE
      WHILE nIndex <= Len( cJson )
         cChar := SubStr( cJson, nIndex, 1 )
         IF cChar $ " :"
            EXIT
         ENDIF
         cKey += cChar
         nIndex++
      ENDDO
   ENDIF
   RETURN cKey

STATIC FUNCTION RelaxedParseString( cJson, nIndex, cQuoteType )
   LOCAL cStr := "", cChar
   nIndex++ 
   WHILE nIndex <= Len( cJson )
      cChar := SubStr( cJson, nIndex, 1 )
      IF cChar == cQuoteType
         nIndex++
         EXIT
      ENDIF
      cStr += cChar
      nIndex++
   ENDDO
   RETURN cStr

STATIC FUNCTION RelaxedParseNumber( cJson, nIndex )
   LOCAL cNum := "", cChar
   WHILE nIndex <= Len( cJson )
      cChar := SubStr( cJson, nIndex, 1 )
      IF !(cChar $ "+-0123456789.eE")
         EXIT
      ENDIF
      cNum += cChar
      nIndex++
   ENDDO
   RETURN Val( cNum )

STATIC FUNCTION RelaxedParseLiteral( cJson, nIndex )
   LOCAL cLiteral := "", cChar, xRet := NIL
   WHILE nIndex <= Len( cJson )
      cChar := SubStr( cJson, nIndex, 1 )
      IF cChar $ " ,]}"
         EXIT
      ENDIF
      cLiteral += cChar
      nIndex++
   ENDDO
   cLiteral := Lower( cLiteral )
   IF cLiteral == "true"
      xRet := .T.
   ENDIF
   IF cLiteral == "false"
      xRet := .F.
   ENDIF
   RETURN xRet
   
   
// +--------------------------------------------------------------------
// + Função: hb_ArrayToLine
// + Objetivo: Converter um Array em uma string delimitada (Polyfill)
// +--------------------------------------------------------------------
STATIC FUNCTION hb_ArrayToLine( aArray, cDelim )
   LOCAL cLine := ""
   LOCAL nI, nLen

   // Validação de segurança
   IF ValType( aArray ) <> "A"
      RETURN ""
   ENDIF

   // Delimitador padrão caso não seja informado
   IF ValType( cDelim ) <> "C"
      cDelim := "|"
   ENDIF

   nLen := Len( aArray )
   
   // Concatenação otimizada
   FOR nI := 1 TO nLen
      cLine += hb_ValToStr( aArray[ nI ] )
      IF nI < nLen
         cLine += cDelim
      ENDIF
   NEXT

   RETURN cLine   