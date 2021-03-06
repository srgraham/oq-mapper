// Functions ------------------------------
{
	var flatten = function (arr) {
    if (arr == null) { return null; }
    return arr.reduce(function(a, b) {
      return Array.isArray(b) ? a.concat(flatten(b)) : a.concat(b);
    }, []).filter(function(item) {
      return !Array.isArray(item) && item != null && item !== "\n";
    });
  };
  
  var parseTagInComment = function(comment) {
    var matches = comment.match(/`(.*)`/g);
    var meta = matches != null ? matches.map(function(item) {
      return item.replace(/`/g, "")
        .replace(/'/g, "")
        .replace(/\\n/g, " ")
        .split(" ")
        .filter(function(item) {
          return item.length > 0;
        })
        .map(function(item) {
          var splitted = item.split(":");
          var obj = {};
          obj[splitted[0]] = splitted[1];
          return obj;
        });
    }) : [];
    return flatten(meta);
  }
  
  var genNumberType = function (type, length, sign) {
    var numberType = {
      type: type.toLowerCase(),
      sign: sign,
      length: length,
      min: 0,
      max: 0,
      bites: 0
    };
    switch (numberType.type) {
      case "int":
        numberType.min = sign === "unsigned" ? 0 : -2147483648;
        numberType.max = sign === "unsigned" ? 4294967295 : 2147483647;
        numberType.bites = 4;
        break;
      case "tinyint":
        numberType.min = sign === "unsigned" ? 0 : -128;
        numberType.max = sign === "unsigned" ? 255 : 127;
        numberType.bites = 1;
        break;
      case "bigint":
        numberType.min = sign === "unsigned" ? 0 : -1 * Math.pow(2, 63);
        numberType.max = sign === "unsigned" ? Math.pow(2, 64) : -1 * Math.pow(2, 63) - 1;
        numberType.bites = 1;
        break;
      default:
        throw new Error(`Unknown genNumberType() type '${numberType.type}'`)
    }
    return numberType;
  }

  var genStringType = function (type, length) {
    var stringType = {
      type: type.toLowerCase(),
      length: length
    }
    switch (stringType.type) {
      case "varchar":
      case "char":
      case "tinytext":
        stringType.length = Math.pow(2, 8) -1
        break;

      case "text":
        stringType.length = Math.pow(2, 16) - 1
        break;
      case "mediumtext":
        stringType.length = Math.pow(2, 24) - 1
        break;
      case "longtext":
        stringType.length = Math.pow(2, 32) - 1
        break;
      default:
        throw new Error(`Unknown genStringType() type '${stringType.type}'`)
    }
    return stringType;
  }

  var genDecimalType = function (type, length, decimals) {
    var decimalType = {
      type: type.toLowerCase(),
      length: length,
    }

    var isDecimalsSet = (typeof decimals !== 'undefined');

    if (isDecimalsSet) {
      decimalType.decimals = decimals
    }
    switch (decimalType.type) {
      case "real":
      case "double":
      case "float":
        if(!isDecimalsSet) {
          throw new Error(`Type ${decimalType.type} is required to have a decimals parameter`)
        }
        break;
      case "decimal":
      case "numeric":
        break;
      default:
        throw new Error(`Unknown genDecimalType() type '${decimalType.type}'`)
    }

    return decimalType;
  }
    
  var currentTimeStamp = function() {
    var date = new Date();
    var year = date.getFullYear();
    var month = ("00" + date.getMonth()).slice(-2);
    var day = ("00" + date.getDay()).slice(-2);
    var hours = ("00" + date.getHours()).slice(-2);
    var minutes = ("00" + date.getMinutes()).slice(-2);
    var seconds = ("00" + date.getSeconds()).slice(-2);
    return `${year}-${month}-${day} ${hours}:${minutes}:${seconds}`;
  }
  
  var flattenParams = function(head, tail) {
    var rest = tail.length > 0 ? tail.reduce(function(prev, next) {
		return prev.concat(next);
    }, []).join("").split(",").filter(function(item){ return item !== ""; }) : [];
    return [head, ...rest];
  }
  
  var genIndex = function(key, head, tail, isUnique, length) {
    var keys = flattenParams(head, tail);
    var index = {
      type: "index",
      name: key,
      keys: keys,
      unique: isUnique,
      length: length,
    };
    return index;
  }
  
  var genDefaultValue = function(type, allowNull) {
    var zeroValue = null;
    if (allowNull === true) {
      zeroValue = null;
    } else {
      switch(type["type"]) {
        case "varchar":
          zeroValue = "";
          break;
        case "int":
        case "tinyint":
          zeroValue = 0;
          break;
        case "date":
        case "datetime":
          zeroValue = "CURRENT_TIMESTAMP"; // Currently use CURRENT_TIMESTAMP
          break;
      }
    }
    return { default: zeroValue };
  }
}


// Start ------------------------------
Start
  = __ queries:Queries __ {
    return queries;
  }
  
// Queries ------------------------------
Queries
  = body: SourceElements? {
  	return flatten(body);
  }
  
// SourceElements ------------------------------
SourceElements
  = SourceElement (__ SourceElement)*
  
SourceElement
  = Statement
  
// Statements ------------------------------

Statement
  = 
  CommentOut
  / SetStatement
  / CreateStatement
  / CreateTableStatement
  / AlterStatement
  / DropStatement
  / TruncateStatement
  / TransactionStatement
  / UseStatement
  / DelimiterStatement
  / ShowStatement
  / EmptyStatement

EmptyStatement = _ ";"

SetStatement = SetToken _ any  { return null; }
CreateStatement
  = 
      (
  	    CreateToken _ SchemaToken _ any EOS
      ) { return null; }
      /
      (
        CreateToken _ DefinerToken _ "=" _ any _ TriggerToken _ TableName _ (
          AfterToken _ InsertToken _ OnToken
        ) { return null; }
      )
      
CreateTableStatement
  =  CreateToken _ TableToken _ (
    IfToken _ NotToken _ ExistsToken
    /
    IfToken _ ExistsToken
    /
    ""
  ) _ schema:TableName _ wl
    __ elements:Elements __
  wr __ EngineToken _ "=" _ engines _ ( AutoIncrementToken "=" integer+ / "" ) _ ( DefaultToken _ CharsetToken "=" charsets / "") _ ( CollateToken _ "=" _ collations / "") _ ( RowFormatToken "=" row_formats)?
  EOS {
    var fields = elements.filter(function(element) {
      return element.type !== "pk" && element.type !== "constraint" && element.type !== "index";
    });
    var primaryKey = elements.filter(function(element){
      return element.type === "pk";
    });
    var foreignKey = elements.filter(function(element) {
      var type = element.type;
      type === "constraint" && delete element.type; // Be careful with side effects!
      return type === "constraint";
    });
    var index = elements.filter(function(element) {
      var type = element.type;
      type === "index" && delete element.type; // Be careful with side effects!
      return type === "index";
    });
    if (primaryKey.length > 1) { throw new Error("Primary key must be only 1."); }
    var mapped = Object.assign({}, schema, {
      pk: primaryKey.length ? primaryKey[0]["keys"] : null,
      fields: fields,
      constraint: foreignKey,
      index: index
    });
    console.log("Result:", mapped);
    return mapped;
  }

AlterStatement = AlterToken any { return null; }
DropStatement = DropToken any  { return null; }
TruncateStatement = TruncateToken any  { return null; }
TransactionStatement = StartToken TransactionToken CommitToken EOS  { return null; }
UseStatement = UseToken any  { return null; }
DelimiterStatement = DelimiterToken any  { return null; }
ShowStatement = ShowToken any { return null; }

// Combinations

//// Comment
Comment "Comment" = comment:(CommentStatement / "") {  

  if (comment === "") { return { comment: "", tags: [] }; }
  
  var replaced = comment.replace(/'/g, "").replace(/"/g, "'");
  var tag = parseTagInComment(replaced);
  return {
   comment: replaced,
   tags: tag
 };
 
}

CommentStatement = CommentToken _ chars:anyCharacter {
  return chars;
}

//// Column
Elements = (
  Constraint
  /
  Key
  /
  PrimaryKey
  /
  UniqueIndex
  /
  Index
  /
  Column
)+

Column = _ fieldName:FieldName _ type:Type _ specifiedCharsetValue:CharSetValue _ specifiedCollateValue:CollateValue _ nullRestriction:NullRestriction _ specifiedDefaultValue:DefaultValue _ autoIncrement:AutoIncrement _ meta:Comment _ ( "," / "" ) __ {

  var defaultValue = genDefaultValue(type, nullRestriction);
  if (specifiedDefaultValue !== null) {
  	defaultValue.default = specifiedDefaultValue;
  }

  var collateObj;
  var charsetObj;
  if (specifiedCollateValue !== null) {
    collateObj = {collate : specifiedCollateValue};
  }
  if (specifiedCollateValue !== null) {
    charsetObj = {charset : specifiedCharsetValue};
  }

  var column = Object.assign(
    {},
    fieldName,
    type,
    meta,
    collateObj,
    charsetObj,
    nullRestriction,
    defaultValue,
    autoIncrement
  );
  return column;
}

FieldName = name:ObjectName {
  return {
    name: name
  };
}

DefaultValueStatement = DefaultToken _ val:literal {
  return Array.isArray(val) ? val.filter(function(v) {
    return v !== "";
  }).join("") : val;
}

DefaultValue "default statement" = value:( DefaultValueStatement / "" ) {
  return value !== "" ? value : null;
}

CollateValueStatement = CollateToken _ val:collations {
  return Array.isArray(val) ? val.filter(function(v) {
    return v !== "";
  }).join("") : val;
}

CharsetValueStatement = CharacterSetToken _ val:regularIdentifier {
  return Array.isArray(val) ? val.filter(function(v) {
    return v !== "";
  }).join("") : val;
}

CharSetValue "CharSet statement" = value:( CharsetValueStatement / "" ) {
  return value !== "" ? value : null;
}

CollateValue "collate statement" = value:( CollateValueStatement / "" ) {
  return value !== "" ? value : null;
}

AutoIncrement "auto increment statement" = ai:( AutoIncrementToken / "" ) {
  return ai !== "" ? { autoIncrement: true } : { autoIncrement: false};
}

NullRestriction "null statement" = _ head:( NotToken / "" ) _ tail:( NullToken / "" ) _ {
  return head !== "" ? { allowNull: false } : { allowNull: true };
}

PrimaryKey
  = token:(PrimaryToken _ KeyToken) _ "(" head:ObjectName tail:( __ "," __  ObjectName)*  ")" ( "," / "" ) __ {
      var rest = flattenParams(head, tail);
      var pk = {
        type: "pk",
        keys: rest
      };
      return pk;
  }

Index
  = IndexToken _ identifier:ObjectName _ "(" head:ObjectName _ length:IndexLength _ SortStatement tail:( __ "," __  ObjectName _ SortStatement)* _ ")" ( "," / "" ) __ {
      return genIndex(identifier, head, tail, false, length);
  }
  
Key
  = KeyToken _ identifier:ObjectName _ "(" head:ObjectName _ length:IndexLength _ SortStatement tail:( __ "," __  ObjectName _ SortStatement )* _ ")" ( "," / "" ) __ {
    return genIndex(identifier, head, tail, false, length);
  }

UniqueIndex =
  UniqueToken _ indexObj:Key {
     indexObj.unique = true
     return indexObj
  }
  
SortStatement
  = sort:( AscToken / DescToken / "" ) { return null; }

IndexLength = lengthPieces:(( "(" _ intVal _ ")" ) / "") {
  if(lengthPieces[2]){
    return lengthPieces[2]
  }
  return null
}

Constraint
  = ConstraintToken _ name:ObjectName __
  ForeignToken _ KeyToken _ "(" ihead:ObjectName itail:( __ "," __  ObjectName)* ")" __
  ReferencesToken _ fkTable:TableName _ "(" rhead:ObjectName rtail:( __ "," __  ObjectName)* ")" __
  ( OnToken _ DeleteToken _ ForeignKeyOnAction / "" ) __
  ( OnToken _ UpdateToken _ ForeignKeyOnAction ( "," / "" ) / "" ) ("," / "") __ {
    var identifiers = flattenParams(ihead, itail);
    var refs = flattenParams(rhead, rtail);
    return {
      type: "constraint",
      name: name,
      keys: identifiers,
      refTable: fkTable,
      refKeys: refs
    };
  }

ForeignKeyOnAction
  = NoToken _ ActionToken
  / CascadeToken
  / SetToken _ NullToken
  / ""

// Tokens ------------------------------

SetToken "set token" = ( "SET"i )
CreateToken "create token" =  ( "CREATE"i )
RoleToken "role token" = ( "ROLE"i )
DomainToken "domain token" = ( "DOMAIN"i )
TypeToken "type token" = ( "TYPE"i )
TranslationToken "translation token" = ( "TRANSLATION"i )
ModuleToken "module token" = ( "MODULE"i )
ProcedureToken "procedure token" = ( "PROCEDURE"i )
FunctionToken "function token" = ( "FUNCTION"i )
MethodToken "method token" = ( "METHOD"i )
SpecificToken "specific token" = ( "SPECIFIC"i )
AlterToken "alter token" = ( "ALTER"i )
DropToken "drop token" = ( "DROP"i )
TruncateToken "truncate token" = ( "TRUNCATE"i )
StartToken "start token" = ( "START"i )
TransactionToken "transaction token" = ( "TRANSACTION"i )
CommitToken "commit token" = ( "COMMIT"i )
UseToken "use token" = ( "USE"i )
DelimiterToken "delimiter token" = ( "DELIMITER"i )
SchemaToken "schema token" = ( "SCHEMA"i )
DefaultToken "default token" = ( "DEFAULT"i )
CollateToken "default token" = ( "COLLATE"i )
CharacterSetToken "default token" = ( "CHARACTER SET"i )
RowFormatToken "default token" = ( "ROW_FORMAT"i )
CharacterToken "character token" = ( "CHARACTER"i )
TableToken "table token" = ( "TABLE"i )
IfToken "if token" = ( "IF"i )
ElseToken "else token" = ( "ELSE"i )
CaseToken "case token" = ( "CASE"i )
WhenToken "when token" = ( "WHEN"i )
NotToken "not token" = ( "NOT"i )
ExistsToken "exists token" = ( "EXISTS"i )
NullToken "null token" = ( "NULL"i )
PrimaryToken "primary token" = ( "PRIMARY"i )
KeyToken "key token" = ( "KEY"i )
UniqueToken "unique token" = ( "UNIQUE"i )
IndexToken "index token" = ( "INDEX"i )
ConstraintToken "constraint token" = ( "CONSTRAINT"i )
ForeignToken "foreign token" = ( "FOREIGN"i )
ReferencesToken "references token" = ( "REFERENCES"i )
AscToken "asc token" = ( "ASC"i )
DescToken "desc token" = ( "DESC"i )
AutoIncrementToken "auto increment token" = ( "AUTO_INCREMENT"i )
EngineToken "engine token" = ( "ENGINE"i )
InsertToken "insert token" = ( "INSERT"i )
IntoToken "into token" = ( "INTO"i )
SelectToken "select token" = ( "SELECT"i )
UpdateToken "update token" = ( "UPDATE"i )
DeleteToken "delete token" = ( "DELETE"i )
BeginToken "begin token" = ( "BEGIN"i )
EndToken "end token" = ( "END"i )
JoinToken "join token" = ( "JOIN"i )
LeftToken "left token" = ( "LEFT"i )
RightToken "right token" = ( "RIGHT"i )
InnerToken "inner token" = ( "INNER"i )
OnToken "on token" = ( "ON"i )
WhereToken "where token" = ( "WHERE"i )
InToken "in token" = ( "IN"i )
TriggerToken "trigger token" = ( "TRIGGER"i )
DefinerToken "definer token" = ( "DEFINER"i )
NoToken "no token" = ( "NO"i )
ActionToken "action token" = ( "ACTION"i )
CharsetToken "charset token" = ( "CHARSET"i )
CommentToken "comment token" = ( "COMMENT"i )
VarToken "var token" = ("@")
BeforeToken "before token" = ( "BEFORE"i )
AfterToken "after token" = ( "AFTER"i )
RestrictToken "restrict token" = ( "RESTRICT"i )
CascadeToken "cascade token" = ( "CASCADE"i )
ShowToken "show token" = ( "SHOW"i )
WarningsToken "warning token" = ( "WARNINGS"i)

// Types ------------------------------

Type "types"
  = TypeInt
  / TypeString
  / TypeDecimal
  / TypeEnum
  / DateTime
  / Date
  / Timestamp


TypeInt = type:( "TINYINT"i / "SMALLINT"i / "MEDIUMINT"i / "INT"i / "INTEGER"i / "BIGINT"i ) _ length:Length _ sign:Sign {
  return genNumberType(type, length, sign);
}

TypeString = type:( "VARCHAR"i / "CHAR"i / "TINYTEXT"i / "TEXT"i / "MEDIUMTEXT"i / "LONGTEXT"i ) _ length:Length {
  return genStringType(type, length);
}

TypeDecimal = type:( "REAL"i / "DOUBLE"i / "FLOAT"i / "DECIMAL"i / "NUMERIC"i  ) _
  (
    "("
      length:intVal _
      ( "," _ decimals:intVal)? _
    ")"
  )? {

  if(typeof length == 'undefined') {
    var length = null;
  }
  if(typeof decimals == 'undefined') {
    var decimals = null;
  }
  return genDecimalType(type, length, decimals)
}

EnumValue = literal

TypeEnum = "ENUM"i _ "(" head:EnumValue tail:( __ "," __  EnumValue)* ")" {
  var out = {
    type: 'enum',
    values: flattenParams(head, tail),
  }
  return out;

}

Date = type:( "DATE"i ) {
  return {
    type: type.toLowerCase()
  }
}
DateTime = type:( "DATETIME"i ) {
  return {
    type: type.toLowerCase()
  }
}
Timestamp = type:( "TIMESTAMP"i ) {
  return {
    type: type.toLowerCase()
  }
}

// TypeMeta ------------------------------

Length "Length of value" = length:( "(" intVal ")" / "" ) { return length === "" ? 0 : Number(length.filter(function(item) { return item !== "(" && item !== ")" })[0]); }
Sign "Signed/Unsigned" = sign:( "UNSIGNED"i / "" ) { return sign === "" ? "signed" : "unsigned"; }

// Indentifiers ------------------------------
ObjectName "Identifier" = name:( "`" regularIdentifier "`" / regularIdentifier ) {
  var objectName = Array.isArray(name) ? name.join("").replace(/`/g, "").split(",").join("") : name.replace(/`/g, "").split(",").join("");
  return objectName;
}

ColumnName = identifier:( ObjectName "." ObjectName / ObjectName ) {
  var ret = Array.isArray(identifier) ? {
    tableName: identifier[0],
    columnName: identifier[2]
  } : { tableName: "", columnName: identifier }
  return ret;
}

TableName "table name" = identifier:( ObjectName "." ObjectName / ObjectName ) {
  var ret = Array.isArray(identifier) ? {
    dbName: identifier[0],
    tableName: identifier[2]
  } : { dbName: "", tableName: identifier }
  return ret;
}

// Variables

//// Engines ------------------------------
engines = ("InnoDB" / "MyISAM")

//// Charsets ------------------------------
charsets = ( "utf8mb4" / "utf8" / regularIdentifier )

//// Collations ------------------------------
collations = regularIdentifier

// Row_Format
row_formats = regularIdentifier

//// MySQL Functions
mysqlFunctions = CurrentTimestampFunc
  / NowFunc

NowFunc = ( "NOW"i) ( "()" / "" )
CurrentTimestampFunc = ( "CURRENT_TIMESTAMP"i ) ("()" / "")

// Utilities ------------------------------

EOS "End of statement"
  = __ ";"
  / __ "$$"
  / _ SingleLineComment? LineTerminatorSequence
  / _ &")"
  / __ EOF

EOF
  = !.

__
  = ( (WhiteSpace / LineTerminatorSequence / CommentOut / MultiLineDelimiter / MultiLineTransaction)* ) { return null; }

_
  = ( (
  WhiteSpace
  / MultiLineCommentNoLineTerminator
  / MultiLineDelimiterNoLineTerminator
  / MultiLineTransactionNoLineTerminator)* ) { return null; }

WhiteSpace "Whitespace"
  = 
  ws:("\t"
  / "\v"
  / "\f"
  / " "
  / "\u00A0"
  / "\uFEFF"
  / Zs)

// Separator, Space
Zs = [\u0020\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000]

LineTerminator
  = [\n\r\u2028\u2029]

LineTerminatorSequence "End of line"
  = "\n"
  / "\r\n"
  / "\r"
  / "\u2028"
  / "\u2029"
  
CommentOut "Comment out"
  = comments:( MultiLineComment
  / SingleLineComment ) {
    return null;
  }

MultiLineComment
  = "/*" (!"*/" SourceCharacter)* "*/"

MultiLineCommentNoLineTerminator "Open mulit-line comment"
  = "/*" (!("*/" / LineTerminator) SourceCharacter)* "*/"

SingleLineComment "Single-line comment"
  = "--" (!LineTerminator SourceCharacter)*

DelimiterStart = DelimiterToken _ "$$"
DelimiterEnd = DelimiterToken _ ";"

MultiLineDelimiter
  = DelimiterStart (!DelimiterEnd SourceCharacter)* DelimiterEnd
  
MultiLineDelimiterNoLineTerminator "Open mulit-line delimiter"
  = DelimiterStart (!(DelimiterEnd / LineTerminator) SourceCharacter)* DelimiterEnd

StartTransaction = StartToken _ TransactionToken __ EOS
Commit = CommitToken __ EOS

MultiLineTransaction
  = StartTransaction (!Commit SourceCharacter)* Commit

MultiLineTransactionNoLineTerminator "Open mulit-line transaction"
  = StartTransaction (!(Commit / LineTerminator) SourceCharacter)* Commit

SourceCharacter
  = .

integer "Integer"
  = [0-9]

digit "Digit"
  = [0-9]

floatVal "Float"
  = digit* "." digit+

intVal "Int"
  = int:integer+ {
    return int.join("");
  }

letter "Letter"
  = [a-zA-Z]

anyCharacter "Any characters"
  = chars:( ("'" (!"'" SourceCharacter)* "'") / ('"' (!'"' SourceCharacter)* '"') ) {
  	var flattened = flatten(chars);
    return flattened.join("");
  }
  
commentCharacters = chars:("'" (!"'" SourceCharacter)* "'")
  
defaultValue = anyCharacter / floatVal / intVal / mysqlFunctions / NullToken


unescapedChar "unescapedChar" = [^\0-\x1F\x22\x5c]

escape = "\\"

char "Char"
  = unescapedChar
  / escape
    sequence:(
      doubleQuote
    / singleQuote
    )
    {return sequence}
  / singleQuote singleQuote { return "'"; }
  / doubleQuote doubleQuote { return '"'; }

doubleQuote "DoubleQuote" = "\""
singleQuote "SingleQuote" = "'"

doubleQuotedString "doubleQuotedString" = doubleQuote chars:(!doubleQuote c:char{return c})* doubleQuote { return chars.join(""); }
singleQuotedString "singleQuotedString" = singleQuote chars:(!singleQuote c:char{return c})* singleQuote { return chars.join(""); }

string = (singleQuotedString / doubleQuotedString)

hexDigit = [a-f0-9]i

hexLiteral
  = hexDigits:( "X"i singleQuote hexDigitsInner:(hexDigit+) singleQuote {return hexDigitsInner}
    / "0x"i hexDigitsInner:(hexDigit+) {return hexDigitsInner}
    ){
      if(hexDigits.length % 2 == 1) {
        hexDigits.unshift('0');
      }
      var arr = []
      for(var i=0; i < hexDigits.length; i+=2 ) {
        var byteVal = parseInt(hexDigits[i], 16) * 16 + parseInt(hexDigits[i + 1], 16);
        arr.push(byteVal);
      }
      return new Buffer(arr)
    }


floatLiteral "FloatLiteral" = val:(digit* "." digit+ ) { return Number(val.join('')) }
integerLiteral "IntegerLiteral" = val:(digit+) { return Number(val.join('')) }
numericLiteral "NumericLiteral" = val:(floatLiteral / integerLiteral) { return Number(val) }

functionLiteral "FunctionLiteral" = val:(regularIdentifier "()") {return text()}

literal
  = string
  / "d9"
  / hexLiteral
  / numericLiteral
  // date
  // bitLiteral
  // boolLiterals
  / NullToken {return null}
  / functionLiteral

// Any does not consume any input
any "Any"
  = (!EOS SourceCharacter)* EOS  { return null; }

regularIdentifier "Regular Identifier"
  = [a-zA-Z0-9_]+

wl = "(" { return null; }
wr = ")" { return null; }