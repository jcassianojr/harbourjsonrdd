/*
 * Classe: JSONClass
 * Objetivo: Leitura de arquivos JSON com cursor DBF-like.
 * Arquitetura: Interface polimórfica com CSVClass, mas com construtor enxuto e específico.
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

   // Construtor limpo: recebe apenas o que o motor JSON realmente consome
   METHOD New( cFileName, lHeader, lRetornaTipado, aManualHeader )
   
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

METHOD New( cFileName, lHeader, lRetornaTipado, aManualHeader ) CLASS JSONClass
   ::cFile         := cFileName
   ::lHasHeader    := hb_DefaultValue( lHeader, .T. )
   ::lTyped        := hb_DefaultValue( lRetornaTipado, .F. )
   ::aManualHeader := hb_DefaultValue( aManualHeader, {} )
   
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
   LOCAL xRecord, cLine := "", nX
   
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
      
   // Se for Array de valores, une usando o delimitador
   ELSEIF ValType( xRecord ) == "A"
      FOR nX := 1 TO Len( xRecord )
         cLine += hb_ValToStr( xRecord[ nX ] )
         IF nX < Len( xRecord )
            cLine += cDelim
         ENDIF
      NEXT
      
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

   cContent := MemoRead( ::cFile )
   xDecoded := hb_jsonDecode( cContent )

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
               cName := "CAMPO" + AllTrim( Str( nI ) )
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
   IF ValType( nRows ) <> "N"; nRows := 1; ENDIF
   IF ::nTotalRecords == 0; RETURN NIL; ENDIF

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

   // --- LOGICA DE TIPAGEM CORRIGIDA ---
   IF ::lTyped
      cType := ::aStruct[ nFieldPos, 3 ]
      
      // 1. Tipagem forcada pelo Cabecalho Manual
      IF cType == "D"
         xVal := ::StrDate( xRawVal )
      ELSEIF cType == "L"
         xVal := ::StrLogic( xRawVal, .F. )
      ELSEIF cType == "N"
         xVal := Val( hb_ValToStr( xRawVal ) )
         
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
   LOCAL aRow := {}, nI
   IF !::lEof
      FOR nI := 1 TO ::nFields
         AAdd( aRow, ::FieldGet( nI ) )
      NEXT
   ENDIF
RETURN aRow

METHOD StrLogic( cVal, lDefault ) CLASS JSONClass
   IF ValType( lDefault ) <> "L"; lDefault := .F.; ENDIF
   cVal := AllTrim( cVal )
   
   SWITCH Upper( cVal )
   CASE ".T."; CASE "TRUE"; CASE "YES"; CASE "SIM"; CASE "ON"; CASE "Y"; CASE "1"; CASE "T"; CASE "S"
      RETURN .T.
   CASE ".F."; CASE "FALSE"; CASE "NO"; CASE "NAO"; CASE "OFF"; CASE "N"; CASE "0"; CASE "F"; CASE "<NULL>"; CASE "NULL"
      RETURN .F.
   ENDSWITCH
RETURN lDefault

METHOD StrDate( xData ) CLASS JSONClass
   LOCAL dRet := CToD( "" ), cTemp, aParts, cAno, cMes, cDia, nAno

   IF ValType( xData ) == "D"; RETURN xData; ENDIF
   IF ValType( xData ) <> "C" .OR. Empty( xData ) .OR. xData == "NULL"; RETURN dRet; ENDIF

   xData := AllTrim( xData )
   cTemp := StrTran( xData, "-", "/" )
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
      IF cAno + cMes + cDia == "00000000"; RETURN dRet; ENDIF
      RETURN SToD( cAno + cMes + cDia )
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