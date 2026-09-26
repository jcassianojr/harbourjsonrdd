/*
 * Classe: JSONClass
 * Objetivo: Leitura de arquivos JSON com cursor DBF-like.
 * Arquitetura: Interface polimórfica com CSVClass, mas com construtor enxuto e específico.
 * Atualização: Buffer via Arrays, Proteção Numérica e Fallback Híbrido para JSON Tolerante.
 */

#include "hbclass.ch"

CREATE CLASS JSONClass

   VAR cFile
   VAR aData            
   VAR aStruct          
   VAR nTotalRecords
   VAR nFields
   VAR nRecNo
   VAR lHasHeader       
   VAR lTyped
   VAR aManualHeader    
   VAR cJsonType        
   VAR lEof
   VAR lBof
   VAR lStoreLargeNums  // Proteção de integridade numérica

   // Construtor limpo: recebe apenas o que o motor JSON realmente consome
   METHOD New( cFileName, lHeader, lRetornaTipado, aManualHeader, lStoreLargeNums )
   
   // --- Interface Polimorfica (Idêntica ao CSVClass) ---
   METHOD Open()
   METHOD Close()
   METHOD GoTop()
   METHOD GoBottom()
   METHOD Skip( nRows )
   METHOD GoTo( nRec )
   METHOD Eof()         INLINE ::lEof
   METHOD Bof()         INLINE ::lBof
   METHOD RecNo()       INLINE ::nRecNo
   METHOD LastRec()

   METHOD FieldName( nFieldPos )
   METHOD FieldPos( cFieldName )
   METHOD FieldGet( nFieldPos )
   METHOD GetRow()
   
   // --- Motor Interno ---
   METHOD StrLogic( cVal, lDefault )
   METHOD StrDate( xData )
   
   METHOD GetLine( cDelim )
   METHOD GetStructOriginal() INLINE ::aStruct

ENDCLASS

METHOD New( cFileName, lHeader, lRetornaTipado, aManualHeader, lStoreLargeNums ) CLASS JSONClass
   ::cFile           := cFileName
   ::lHasHeader      := hb_DefaultValue( lHeader, .T. )
   ::lTyped          := hb_DefaultValue( lRetornaTipado, .F. )
   ::aManualHeader   := hb_DefaultValue( aManualHeader, {} )
   ::lStoreLargeNums := hb_DefaultValue( lStoreLargeNums, .F. )
   
   ::aData         := {}
   ::aStruct       := {}
   ::nTotalRecords := 0
   ::nFields       := 0
   ::nRecNo        := 0
   ::cJsonType     := ""
   ::lEof          := .F.
   ::lBof          := .T.
RETURN Self

// +--------------------------------------------------------------------
// + Retorna o registro atual do JSON em formato de string/linha formatada
// +--------------------------------------------------------------------
METHOD GetLine( cDelim ) CLASS JSONClass
   LOCAL xRecord, cLine := "", nX, aBuffer
   
   IF ValType( cDelim ) <> "C" .OR. Empty( cDelim )
      cDelim := "|" // Padrão pipe se não informado
   ENDIF

   IF ::nRecNo < 1 .OR. ::lEof
      RETURN ""
   ENDIF

   xRecord := ::aData[ ::nRecNo ]
   
   // Se for Objeto/Hash, serializa o nó atual como string JSON
   IF ValType( xRecord ) == "H"
      cLine := hb_jsonEncode( xRecord, .F. )
      
   // Se for Array de valores, une usando o delimitador com otimização ArrayToLine
   ELSEIF ValType( xRecord ) == "A"
      aBuffer := Array( Len( xRecord ) )
      FOR nX := 1 TO Len( xRecord )
         aBuffer[ nX ] := hb_ValToStr( xRecord[ nX ] )
      NEXT
      cLine := hb_ArrayToLine( aBuffer, cDelim )
      
   // Fallback para valores literais
   ELSE
      cLine := hb_ValToStr( xRecord )
   ENDIF
   
   RETURN cLine

METHOD Open() CLASS JSONClass
   LOCAL cContent, xDecoded, xFirstRow, aKeys, nI, cName

   IF !File( ::cFile )
      RETURN .F.
   ENDIF

   // 1. Leitura Nativa e Fast Path
   cContent := MemoRead( ::cFile )
   xDecoded := hb_jsonDecode( cContent )

   // 2. Slow Path (Fallback Híbrido Tolerante)
   IF ValType( xDecoded ) <> "A" .AND. !Empty( cContent )
      xDecoded := RelaxedJsonDecode( cContent )
   ENDIF

   // Aborta se continuar inválido
   IF ValType( xDecoded ) <> "A"
      RETURN .F. 
   ENDIF

   ::aData := xDecoded
   ::nTotalRecords := Len( ::aData )

   IF ::nTotalRecords > 0
      xFirstRow := ::aData[ 1 ]
      ::cJsonType := iif( ValType( xFirstRow ) == "H", "H", "A" )

      // 1. SE O CABEÇALHO FOI PASSADO MANUALMENTE VIA MATRIZ 
      IF Len( ::aManualHeader ) > 0
         
         IF ::lHasHeader .AND. ::cJsonType == "A"
            hb_ADel( ::aData, 1, .T. )
            ::nTotalRecords--
         ENDIF

         ::nFields := Len( ::aManualHeader )
         FOR nI := 1 TO ::nFields
            cName := Upper( Left( AllTrim( ::aManualHeader[ nI ] ), 10 ) )
            IF ::cJsonType == "H"
               AAdd( ::aStruct, { cName, ::aManualHeader[ nI ], "C" } )
            ELSE
               AAdd( ::aStruct, { cName, nI, "C" } )
            ENDIF
         NEXT

      // 2. LEITURA AUTOMATICA DO ARQUIVO JSON
      ELSE
         IF ::cJsonType == "A" .AND. ::lHasHeader
            hb_ADel( ::aData, 1, .T. )
            ::nTotalRecords--
            ::nFields := Len( xFirstRow )
            FOR nI := 1 TO ::nFields
               cName := Upper( Left( AllTrim( hb_ValToStr( xFirstRow[ nI ] ) ), 10 ) )
               AAdd( ::aStruct, { cName, nI, "C" } )
            NEXT
         ELSEIF ::cJsonType == "H"
            aKeys := hb_HKeys( xFirstRow )
            ::nFields := Len( aKeys )
            FOR nI := 1 TO ::nFields
               cName := Upper( Left( AllTrim( aKeys[ nI ] ), 10 ) )
               AAdd( ::aStruct, { cName, aKeys[ nI ], "C" } )
            NEXT
         ELSEIF ::cJsonType == "A"
            ::nFields := Len( xFirstRow )
            FOR nI := 1 TO ::nFields
               cName := "CAMPO" + AllTrim( StrZERO( nI,3 ) )
               AAdd( ::aStruct, { cName, nI, "C" } )
            NEXT
         ENDIF
      ENDIF
   ENDIF

   ::GoTop()
RETURN .T.

METHOD Close() CLASS JSONClass
   ::aData := {}
   ::aStruct := {}
   ::nTotalRecords := 0
   ::lEof := .T.
RETURN NIL

METHOD GoTop() CLASS JSONClass
   IF ::nTotalRecords > 0
      ::nRecNo := 1
      ::lEof := .F.
      ::lBof := .T.
   ELSE
      ::nRecNo := 0
      ::lEof := .T.
      ::lBof := .T.
   ENDIF
RETURN NIL

METHOD GoBottom() CLASS JSONClass
   IF ::nTotalRecords > 0
      ::nRecNo := ::nTotalRecords
      ::lEof := .F.
      ::lBof := .F.
   ELSE
      ::nRecNo := 0
      ::lEof := .T.
   ENDIF
RETURN NIL

METHOD Skip( nRows ) CLASS JSONClass
   IF ValType( nRows ) <> "N"
      nRows := 1
   ENDIF
   IF ::nTotalRecords == 0
      RETURN NIL
   ENDIF

   ::nRecNo += nRows
   ::lBof := .F.

   IF ::nRecNo > ::nTotalRecords
      ::nRecNo := ::nTotalRecords + 1 
      ::lEof := .T.
   ELSEIF ::nRecNo < 1
      ::nRecNo := 0 
      ::lEof := .F.
      ::lBof := .T.
   ELSE
      ::lEof := .F.
   ENDIF
RETURN NIL

METHOD GoTo( nRec ) CLASS JSONClass
   IF nRec >= 1 .AND. nRec <= ::nTotalRecords
      ::nRecNo := nRec
      ::lEof := .F.
      ::lBof := .F.
   ELSEIF nRec > ::nTotalRecords
      ::nRecNo := ::nTotalRecords + 1
      ::lEof := .T.
   ENDIF
RETURN NIL

METHOD LastRec() CLASS JSONClass
   RETURN ::nTotalRecords

METHOD FieldName( nFieldPos ) CLASS JSONClass
   IF nFieldPos >= 1 .AND. nFieldPos <= ::nFields
      RETURN ::aStruct[ nFieldPos, 1 ]
   ENDIF
RETURN ""

METHOD FieldPos( cFieldName ) CLASS JSONClass
   cFieldName := Upper( AllTrim( cFieldName ) )
   RETURN AScan( ::aStruct, {|x| x[ 1 ] == cFieldName } )

METHOD FieldGet( nFieldPos ) CLASS JSONClass
   LOCAL xRecord, xVal, xRawVal, cType

   IF ::nRecNo < 1 .OR. ::lEof .OR. nFieldPos < 1 .OR. nFieldPos > ::nFields
      RETURN NIL
   ENDIF

   xRecord := ::aData[ ::nRecNo ]

   // Extrai o dado cru
   IF ::cJsonType == "H"
      IF hb_HHasKey( xRecord, ::aStruct[ nFieldPos, 2 ] )
         xRawVal := hb_HGet( xRecord, ::aStruct[ nFieldPos, 2 ] )
      ELSE
         xRawVal := ""
      ENDIF
   ELSEIF ::cJsonType == "A"
      IF Len( xRecord ) >= nFieldPos
         xRawVal := xRecord[ nFieldPos ]
      ELSE
         xRawVal := ""
      ENDIF
   ENDIF

   // --- LOGICA DE TIPAGEM CORRIGIDA COM SUPORTE A LARGEMUNS ---
   IF ::lTyped
      cType := ::aStruct[ nFieldPos, 3 ]
      
      // 1. Tipagem forcada pelo Cabecalho Manual
      IF cType == "D"
         xVal := ::StrDate( xRawVal )
      ELSEIF cType == "T" .OR. cType == "@"
         xVal := UniversalDateTime( xRawVal )
      ELSEIF cType == "L"
         xVal := ::StrLogic( xRawVal, .F. )
      ELSEIF cType == "N"
         // Proteção para evitar truncagem de ponto flutuante
         IF ::lStoreLargeNums .AND. ValType( xRawVal ) == "C" .AND. Len( AllTrim( xRawVal ) ) >= 16
            xVal := xRawVal
         ELSE
            xVal := Val( hb_ValToStr( xRawVal ) )
         ENDIF
         
      // 2. Tipagem Dinamica (Inferencia)
      ELSEIF ValType( xRawVal ) == "C"
         IF IsDigit( Left( AllTrim( xRawVal ), 1 ) ) .AND. ("/" $ xRawVal .OR. "-" $ xRawVal)
            xVal := ::StrDate( xRawVal ) 
         ELSE
            // Usa o motor StrLogic. Se nao for logico, devolve a propria string!
            xVal := ::StrLogic( xRawVal, xRawVal )
         ENDIF
      ELSE
         xVal := xRawVal // Mantem native types (Ex: Numeros e Bools nativos do JSON)
      ENDIF
   ELSEIF !::lTyped
      xVal := hb_ValToStr( xRawVal ) // Força String se lTyped for .F.
   ELSE
      xVal := xRawVal 
   ENDIF

RETURN xVal

METHOD GetRow() CLASS JSONClass
   LOCAL aRow := Array( ::nFields ), nI
   IF !::lEof
      FOR nI := 1 TO ::nFields
         aRow[ nI ] := ::FieldGet( nI )
      NEXT
   ENDIF
RETURN aRow

METHOD StrLogic( cVal, lDefault ) CLASS JSONClass
   IF ValType( lDefault ) <> "L"
      lDefault := .F.
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
      RETURN .F.
   ENDSWITCH
RETURN lDefault

METHOD StrDate( xData ) CLASS JSONClass
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
   cTemp := StrTran( cTemp, ",", " " )
   cTemp := StrTran( cTemp, "-", " " )

   DO WHILE "  " $ cTemp
      cTemp := StrTran( cTemp, "  ", " " )
   ENDDO

   aParts := hb_ATokens( AllTrim( cTemp ), " " )

   IF Len( aParts ) >= 4
      FOR i := 1 TO Len( aParts )
         cMesStr := Upper( Left( aParts[ i ], 3 ) )
         nMes := AScan( aMonthsEN, cMesStr )
         IF nMes == 0
            nMes := AScan( aMonthsPT, cMesStr )
         ENDIF
         IF nMes > 0
            cMes := StrZero( nMes, 2 )
            IF i == 2 .AND. Len( aParts ) >= 5
               cDia := StrZero( Val( aParts[ 3 ] ), 2 )
               cAno := aParts[ 5 ]
            ELSEIF i == 3 
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

   cTemp := AllTrim( xData ) 
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
   dData := StrDate( cDataLimpa )

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