/*
 * Classe: JSONClass
 * Objetivo: Leitura de arquivos JSON com cursor DBF-like e interface unificada (Polimorfismo com CSVClass).
 */

#include "hbclass.ch"

CREATE CLASS JSONClass

   VAR cFile
   VAR aData            
   VAR aStruct          
   VAR nTotalRecords
   VAR nFields
   VAR nRecNo
   VAR cDelim           // Mantido para paridade de propriedades
   VAR cLineDelim       // Mantido para paridade
   VAR lHasHeader       
   VAR lTyped
   VAR lUseSplit        // Mantido para paridade
   VAR cJsonType        
   VAR lEof
   VAR lBof

   // Assinatura rigorosamente identica a CSVClass
   METHOD New( cFileName, cDelimiter, lHeader, lRetornaTipado, lSplit, cLineDelimiter )
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
   
   // Motor Interno de conversao
   METHOD StrLogic( cVal, lDefault )
   METHOD StrDate( xData )

ENDCLASS

METHOD New( cFileName, cDelimiter, lHeader, lRetornaTipado, lSplit, cLineDelimiter ) CLASS JSONClass
   ::cFile      := cFileName
   ::cDelim     := hb_DefaultValue( cDelimiter, "" )
   ::lHasHeader := hb_DefaultValue( lHeader, .T. )
   ::lTyped     := hb_DefaultValue( lRetornaTipado, .F. )
   ::lUseSplit  := hb_DefaultValue( lSplit, .F. )
   ::cLineDelim := hb_DefaultValue( cLineDelimiter, "" )
   
   ::aData         := {}
   ::aStruct       := {}
   ::nTotalRecords := 0
   ::nFields       := 0
   ::nRecNo        := 0
   ::cJsonType     := ""
   ::lEof          := .F.
   ::lBof          := .T.
RETURN Self

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

   IF ::nTotalRecords > 0 .AND. ::lHasHeader .AND. ValType( ::aData[ 1 ] ) == "A"
      xFirstRow := ::aData[ 1 ]
      hb_ADel( ::aData, 1, .T. )
      ::nTotalRecords--
      ::cJsonType := "A"
      ::nFields := Len( xFirstRow )
      FOR nI := 1 TO ::nFields
         cName := Upper( Left( AllTrim( hb_ValToStr( xFirstRow[ nI ] ) ), 10 ) )
         AAdd( ::aStruct, { cName, nI, "C" } )
      NEXT

   ELSEIF ::nTotalRecords > 0
      xFirstRow := ::aData[ 1 ]
      
      IF ValType( xFirstRow ) == "H"
         ::cJsonType := "H"
         aKeys := hb_HKeys( xFirstRow )
         ::nFields := Len( aKeys )
         FOR nI := 1 TO ::nFields
            cName := Upper( Left( AllTrim( aKeys[ nI ] ), 10 ) )
            AAdd( ::aStruct, { cName, aKeys[ nI ], "C" } )
         NEXT
      ELSEIF ValType( xFirstRow ) == "A"
         ::cJsonType := "A"
         ::nFields := Len( xFirstRow )
         FOR nI := 1 TO ::nFields
            cName := "CAMPO" + AllTrim( Str( nI ) )
            AAdd( ::aStruct, { cName, nI, "C" } )
         NEXT
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
   LOCAL xRecord, xVal, xRawVal

   IF ::nRecNo < 1 .OR. ::lEof .OR. nFieldPos < 1 .OR. nFieldPos > ::nFields
      RETURN NIL
   ENDIF

   xRecord := ::aData[ ::nRecNo ]

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

   IF ::lTyped .AND. ValType( xRawVal ) == "C"
      IF IsDigit( Left( AllTrim( xRawVal ), 1 ) ) .AND. ("/" $ xRawVal .OR. "-" $ xRawVal)
         xVal := ::StrDate( xRawVal ) 
      ELSEIF Upper( AllTrim( xRawVal ) ) $ "TRUE.T.SIM"
         xVal := .T.
      ELSE
         xVal := xRawVal
      ENDIF
   ELSEIF !::lTyped
      xVal := hb_ValToStr( xRawVal )
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
      RETURN .T. //[cite: 3]
   CASE ".F."; CASE "FALSE"; CASE "NO"; CASE "NAO"; CASE "OFF"; CASE "N"; CASE "0"; CASE "F"; CASE "<NULL>"; CASE "NULL"
      RETURN .F. //[cite: 3]
   ENDSWITCH
RETURN lDefault

METHOD StrDate( xData ) CLASS JSONClass
   LOCAL dRet := CToD( "" ), cTemp, aParts, cAno, cMes, cDia, nAno

   IF ValType( xData ) == "D"; RETURN xData; ENDIF //[cite: 3]
   IF ValType( xData ) <> "C" .OR. Empty( xData ) .OR. xData == "NULL"; RETURN dRet; ENDIF //[cite: 3]

   xData := AllTrim( xData )
   cTemp := StrTran( xData, "-", "/" ) //[cite: 3]
   cTemp := StrTran( cTemp, ".", "/" ) //[cite: 3]
   aParts := hb_ATokens( cTemp, "/" ) //[cite: 3]

   IF Len( aParts ) == 3
      IF Len( aParts[ 1 ] ) == 4
         cAno := aParts[ 1 ]
         cMes := StrZero( Val( aParts[ 2 ] ), 2 ) //[cite: 3]
         cDia := StrZero( Val( aParts[ 3 ] ), 2 )
      ELSE
         cDia := StrZero( Val( aParts[ 1 ] ), 2 ) //[cite: 3]
         cMes := StrZero( Val( aParts[ 2 ] ), 2 )
         cAno := aParts[ 3 ]
         IF Len( cAno ) == 2
            nAno := Val( cAno )
            cAno := iif( nAno < 50, "20" + cAno, "19" + cAno ) //[cite: 3]
         ENDIF
      ENDIF
      IF cAno + cMes + cDia == "00000000"; RETURN dRet; ENDIF //[cite: 3]
      RETURN SToD( cAno + cMes + cDia ) //[cite: 3]
   ELSE
      IF Len( cTemp ) == 8
         IF Val( Left( cTemp, 4 ) ) > 1900
            dRet := SToD( cTemp ) //[cite: 3]
         ELSE
            dRet := SToD( Right( cTemp, 4 ) + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) //[cite: 3]
         ENDIF
      ELSEIF Len( cTemp ) == 6
         nAno := Val( Right( cTemp, 2 ) )
         cAno := iif( nAno < 50, "20" + Right( cTemp, 2 ), "19" + Right( cTemp, 2 ) ) //[cite: 3]
         dRet := SToD( cAno + SubStr( cTemp, 3, 2 ) + Left( cTemp, 2 ) ) //[cite: 3]
      ELSE
         dRet := CToD( xData ) //[cite: 3]
      ENDIF
   ENDIF
RETURN dRet