/*
 * tokens.h - Classes de tokens da ApiLang.
 *
 * Os valores começam em 258 para ficarem compatíveis com o Bison, que
 * reserva 0..255 para tokens de um caractere e 256/257 para fim/erro.
 * Quando o analisador sintático (Subproblema 7) for gerado com Bison,
 * este arquivo será substituído pelo apilang.tab.h gerado.
 */
#ifndef APILANG_TOKENS_H
#define APILANG_TOKENS_H

typedef enum {
    TOK_EOF = 0,

    /* --- Palavras reservadas: declarações e controle --- */
    KW_VAL = 258, KW_VAR, KW_DEF, KW_PUB, KW_RETURN,
    KW_IF, KW_ELSE, KW_FOR, KW_FOREACH, KW_IN, KW_MATCH,
    KW_STRUCT, KW_ENUM, KW_IMPORT,
    KW_TRUE, KW_FALSE,

    /* --- Palavras reservadas: tipos primitivos e str ---
     * list, map, set, tuple, uuid, date, time, datetime, Optional e Result
     * NÃO são reservados: são identificadores pré-definidos, resolvidos na
     * tabela de símbolos (assim `lista.map(f)` e um campo `date` continuam
     * válidos). */
    KW_INT, KW_FLOAT, KW_DOUBLE, KW_DECIMAL, KW_BOOL, KW_CHAR, KW_STR,

    /* --- Identificadores e literais --- */
    IDENT,
    INT_LIT,        /* 42, 0x2A, 0b101010, 1_000_000 */
    FLOAT_LIT,      /* 3.14, 1.0e-3, 2e10            */
    STRING_LIT,     /* "texto com \n escapes"        */
    CHAR_LIT,       /* 'a', '\n'                     */

    /* --- Operadores --- */
    OP_PLUS, OP_MINUS, OP_STAR, OP_SLASH, OP_PERCENT,   /* + - * / %     */
    OP_EQ, OP_NE, OP_LT, OP_LE, OP_GT, OP_GE,           /* == != < <= > >= */
    OP_AND, OP_OR, OP_NOT,                              /* && || !       */
    OP_ASSIGN,                                          /* =             */
    OP_ARROW, OP_FAT_ARROW,                             /* -> =>         */
    OP_RANGE, OP_RANGE_INCL,                            /* .. ..=        */
    OP_SCOPE,                                           /* ::            */
    OP_DOT, OP_QUESTION,                                /* . ?           */

    /* --- Delimitadores --- */
    LPAREN, RPAREN, LBRACE, RBRACE, LBRACKET, RBRACKET, /* ( ) { } [ ]  */
    COMMA, SEMICOLON, COLON, AT,                        /* , ; : @      */

    /* Erro léxico: o lexer emite este token e continua a análise */
    TOK_ERROR
} TokenKind;

/* Valor semântico associado ao token (lido pelo parser via yylval). */
typedef union {
    long long  ival;    /* INT_LIT                          */
    double     fval;    /* FLOAT_LIT                        */
    int        cval;    /* CHAR_LIT (código do caractere)   */
    char      *sval;    /* IDENT, STRING_LIT (já sem aspas) */
} TokenValue;

/* Posição do token no arquivo-fonte (1-based). */
typedef struct {
    int first_line, first_column;
    int last_line,  last_column;
} TokenPos;

extern TokenValue yylval;
extern TokenPos   yylloc;
extern int        lex_error_count;

const char *token_name(int kind);
int  yylex(void);

#endif
