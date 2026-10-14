/*
 * apilang.l - Especificação Flex do analisador léxico da ApiLang.
 *
 * Gera: lex.yy.c   (flex apilang.l)
 *
 * Organização:
 *   1. Definições (macros de expressões regulares)
 *   2. Regras: palavras reservadas, literais, operadores, erros
 *   3. Rotinas auxiliares (posição, buffer de string, erros)
 *
 * Desambiguação (como no Lex/Flex, cf. Appel, cap. 2):
 *   - casamento mais longo (longest match): "==" vence "=", "foreach" vence "for";
 *   - prioridade da regra: em empate de tamanho vale a regra que aparece
 *     primeiro, por isso as palavras reservadas vêm antes de {ID}.
 */

%option noyywrap nounput noinput nodefault

%{
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tokens.h"

TokenValue yylval;
TokenPos   yylloc;
int        lex_error_count = 0;
const char *lex_filename = "<stdin>";

/* Posição corrente (linha/coluna do próximo caractere a ser lido). */
static int cur_line = 1, cur_col = 1;

static void update_loc(void);
#define YY_USER_ACTION update_loc();

static void lex_error(const TokenPos *pos, const char *fmt, ...);

/* Buffer para montar o conteúdo de strings (escapes já traduzidos). */
static char  *sbuf = NULL;
static size_t slen = 0, scap = 0;
static void   sbuf_reset(void);
static void   sbuf_add(const char *s, size_t n);
static void   sbuf_add_utf8(unsigned long cp);

static TokenPos str_start;      /* posição da aspa de abertura */
static TokenPos comment_start;  /* posição da abertura do comentário */
static int      comment_depth;  /* comentários de bloco aninham */

static int make_int(const char *text, int base);
static int make_char(const char *body, int len);
%}

/* ---------- Definições ---------- */
DIGIT       [0-9]
DEC         {DIGIT}(_?{DIGIT})*
HEX         0[xX][0-9a-fA-F](_?[0-9a-fA-F])*
BIN         0[bB][01](_?[01])*
EXP         [eE][+-]?{DEC}
FLOAT       ({DEC}"."{DEC}{EXP}?)|({DEC}{EXP})
ID          [A-Za-z_][A-Za-z0-9_]*
/* Sequências UTF-8 multibyte (permitidas em strings, chars e comentários) */
UTF8MB      ([\xC2-\xDF][\x80-\xBF])|([\xE0-\xEF][\x80-\xBF]{2})|([\xF0-\xF4][\x80-\xBF]{3})
/* Caractere ASCII imprimível exceto ' e \ (conteúdo simples de um char) */
CHARSIMPLE  [\x20-\x26\x28-\x5B\x5D-\x7E]
ESCAPE      \\[ntr0\\'"]
UESCAPE     \\u\{[0-9a-fA-F]{1,6}\}

%x STR COMMENT

%%

 /* ---------- Espaços e comentários (descartados) ---------- */
[ \t\r]+                { /* ignora */ }
\n                      { /* ignora */ }
"//"[^\n]*              { /* comentário de linha */ }
"/*"                    { comment_depth = 1; comment_start = yylloc; BEGIN(COMMENT); }
<COMMENT>"/*"           { comment_depth++; }
<COMMENT>"*/"           { if (--comment_depth == 0) BEGIN(INITIAL); }
<COMMENT>[^*/\n]+       { }
<COMMENT>\n             { }
<COMMENT>.              { }
<COMMENT><<EOF>>        { lex_error(&comment_start, "comentário de bloco não terminado (aberto aqui)");
                          yylloc = comment_start;
                          BEGIN(INITIAL); return TOK_ERROR; }

 /* ---------- Palavras reservadas ---------- */
"val"                   { return KW_VAL; }
"var"                   { return KW_VAR; }
"def"                   { return KW_DEF; }
"pub"                   { return KW_PUB; }
"return"                { return KW_RETURN; }
"if"                    { return KW_IF; }
"else"                  { return KW_ELSE; }
"for"                   { return KW_FOR; }
"foreach"               { return KW_FOREACH; }
"in"                    { return KW_IN; }
"match"                 { return KW_MATCH; }
"struct"                { return KW_STRUCT; }
"enum"                  { return KW_ENUM; }
"import"                { return KW_IMPORT; }
"true"                  { return KW_TRUE; }
"false"                 { return KW_FALSE; }

"int"                   { return KW_INT; }
"float"                 { return KW_FLOAT; }
"double"                { return KW_DOUBLE; }
"decimal"               { return KW_DECIMAL; }
"bool"                  { return KW_BOOL; }
"char"                  { return KW_CHAR; }
"str"                   { return KW_STR; }

 /* ---------- Identificadores ---------- */
{ID}                    { yylval.sval = strdup(yytext); return IDENT; }

 /* ---------- Literais numéricos ---------- */
 /* Erros vêm antes das regras válidas quando o tamanho empata. */
0{DIGIT}+               { lex_error(&yylloc, "literal inteiro '%s' com zero à esquerda (não há octal; use 0x/0b ou remova o zero)", yytext);
                          return TOK_ERROR; }
{HEX}                   { return make_int(yytext + 2, 16); }
{BIN}                   { return make_int(yytext + 2, 2); }
{FLOAT}                 { char *clean = strdup(yytext), *w = clean;
                          for (const char *r = yytext; *r; r++) if (*r != '_') *w++ = *r;
                          *w = '\0';
                          errno = 0;
                          yylval.fval = strtod(clean, NULL);
                          free(clean);
                          if (errno == ERANGE) {
                              lex_error(&yylloc, "literal real '%s' fora da faixa de double", yytext);
                              return TOK_ERROR;
                          }
                          return FLOAT_LIT; }
{DEC}                   { return make_int(yytext, 10); }
{DIGIT}[0-9A-Za-z_]*    { lex_error(&yylloc, "literal numérico malformado '%s'", yytext); return TOK_ERROR; }
{DEC}"."{DEC}{EXP}?[A-Za-z_][A-Za-z0-9_]* {
                          lex_error(&yylloc, "literal real malformado '%s'", yytext); return TOK_ERROR; }

 /* ---------- Literais de caractere ---------- */
'{CHARSIMPLE}'          { return make_char(yytext + 1, 1); }
'{UTF8MB}'              { return make_char(yytext + 1, yyleng - 2); }
'{ESCAPE}'              { return make_char(yytext + 1, 2); }
'{UESCAPE}'             { return make_char(yytext + 1, yyleng - 2); }
''                      { lex_error(&yylloc, "literal de caractere vazio"); return TOK_ERROR; }
'[^'\n]+'               { lex_error(&yylloc, "literal de caractere %s deve conter exatamente um caractere (para texto use \"...\")", yytext);
                          return TOK_ERROR; }
'[^'\n]*                { lex_error(&yylloc, "literal de caractere não terminado"); return TOK_ERROR; }

 /* ---------- Literais de string ---------- */
\"                      { sbuf_reset(); str_start = yylloc; BEGIN(STR); }
<STR>\"                 { BEGIN(INITIAL);
                          yylloc.first_line = str_start.first_line;
                          yylloc.first_column = str_start.first_column;
                          yylval.sval = strdup(sbuf);
                          return STRING_LIT; }
<STR>[^\\\"\n]+         { sbuf_add(yytext, yyleng); }
<STR>\\n                { sbuf_add("\n", 1); }
<STR>\\t                { sbuf_add("\t", 1); }
<STR>\\r                { sbuf_add("\r", 1); }
<STR>\\0                { sbuf_add("", 1); }
<STR>\\\\               { sbuf_add("\\", 1); }
<STR>\\\"               { sbuf_add("\"", 1); }
<STR>\\'                { sbuf_add("'", 1); }
<STR>{UESCAPE}          { unsigned long cp = strtoul(yytext + 3, NULL, 16);
                          if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF))
                              lex_error(&yylloc, "escape unicode '%s' inválido", yytext);
                          else
                              sbuf_add_utf8(cp); }
<STR>\\.                { lex_error(&yylloc, "sequência de escape inválida '%s' em string", yytext); }
<STR>\\                 { lex_error(&yylloc, "barra invertida solta no fim da linha"); }
<STR>\n                 { lex_error(&str_start, "string não terminada (quebra de linha antes de fechar aspas)");
                          yylloc = str_start;
                          BEGIN(INITIAL); return TOK_ERROR; }
<STR><<EOF>>            { lex_error(&str_start, "string não terminada (fim de arquivo)");
                          yylloc = str_start;
                          BEGIN(INITIAL); return TOK_ERROR; }

 /* ---------- Operadores ---------- */
"=="                    { return OP_EQ; }
"!="                    { return OP_NE; }
"<="                    { return OP_LE; }
">="                    { return OP_GE; }
"&&"                    { return OP_AND; }
"||"                    { return OP_OR; }
"->"                    { return OP_ARROW; }
"=>"                    { return OP_FAT_ARROW; }
"..="                   { return OP_RANGE_INCL; }
".."                    { return OP_RANGE; }
"::"                    { return OP_SCOPE; }
"+"                     { return OP_PLUS; }
"-"                     { return OP_MINUS; }
"*"                     { return OP_STAR; }
"/"                     { return OP_SLASH; }
"%"                     { return OP_PERCENT; }
"<"                     { return OP_LT; }
">"                     { return OP_GT; }
"!"                     { return OP_NOT; }
"="                     { return OP_ASSIGN; }
"."                     { return OP_DOT; }
"?"                     { return OP_QUESTION; }

 /* ---------- Delimitadores ---------- */
"("                     { return LPAREN; }
")"                     { return RPAREN; }
"{"                     { return LBRACE; }
"}"                     { return RBRACE; }
"["                     { return LBRACKET; }
"]"                     { return RBRACKET; }
","                     { return COMMA; }
";"                     { return SEMICOLON; }
":"                     { return COLON; }
"@"                     { return AT; }

 /* ---------- Erros léxicos com mensagem específica ---------- */
"<>"                    { lex_error(&yylloc, "operador '<>' não existe na ApiLang; use '!='"); return TOK_ERROR; }
"&"                     { lex_error(&yylloc, "operador '&' inválido; o E lógico é '&&'"); return TOK_ERROR; }
"|"                     { lex_error(&yylloc, "operador '|' inválido; o OU lógico é '||'"); return TOK_ERROR; }
({ID})?{UTF8MB}([A-Za-z0-9_]|{UTF8MB})* {
                          lex_error(&yylloc, "'%s': caracteres não-ASCII só são permitidos em strings, chars e comentários (identificadores usam [A-Za-z0-9_])", yytext);
                          return TOK_ERROR; }
.                       { unsigned char c = (unsigned char) yytext[0];
                          if (c >= 0x20 && c < 0x7F)
                              lex_error(&yylloc, "caractere inválido '%c'", c);
                          else
                              lex_error(&yylloc, "byte inválido 0x%02X", c);
                          return TOK_ERROR; }

%%

#include <stdarg.h>

/* Atualiza yylloc com o trecho casado (colunas contam caracteres UTF-8). */
static void update_loc(void)
{
    yylloc.first_line   = cur_line;
    yylloc.first_column = cur_col;
    for (int i = 0; i < yyleng; i++) {
        unsigned char c = (unsigned char) yytext[i];
        if (c == '\n') {
            cur_line++;
            cur_col = 1;
        } else if ((c & 0xC0) != 0x80) {
            cur_col++;
        }
    }
    yylloc.last_line   = cur_line;
    yylloc.last_column = cur_col - 1;
}

static void lex_error(const TokenPos *pos, const char *fmt, ...)
{
    va_list ap;
    fprintf(stderr, "%s:%d:%d: erro léxico: ", lex_filename, pos->first_line, pos->first_column);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    lex_error_count++;
}

static void sbuf_reset(void)
{
    slen = 0;
    if (!sbuf) {
        scap = 64;
        sbuf = malloc(scap);
    }
    sbuf[0] = '\0';
}

static void sbuf_add(const char *s, size_t n)
{
    if (slen + n + 1 > scap) {
        while (slen + n + 1 > scap) scap *= 2;
        sbuf = realloc(sbuf, scap);
    }
    memcpy(sbuf + slen, s, n);
    slen += n;
    sbuf[slen] = '\0';
}

static void sbuf_add_utf8(unsigned long cp)
{
    char out[4];
    size_t n;
    if (cp < 0x80)        { out[0] = (char) cp; n = 1; }
    else if (cp < 0x800)  { out[0] = (char) (0xC0 | (cp >> 6));
                            out[1] = (char) (0x80 | (cp & 0x3F)); n = 2; }
    else if (cp < 0x10000){ out[0] = (char) (0xE0 | (cp >> 12));
                            out[1] = (char) (0x80 | ((cp >> 6) & 0x3F));
                            out[2] = (char) (0x80 | (cp & 0x3F)); n = 3; }
    else                  { out[0] = (char) (0xF0 | (cp >> 18));
                            out[1] = (char) (0x80 | ((cp >> 12) & 0x3F));
                            out[2] = (char) (0x80 | ((cp >> 6) & 0x3F));
                            out[3] = (char) (0x80 | (cp & 0x3F)); n = 4; }
    sbuf_add(out, n);
}

/* Converte literal inteiro (sem prefixo), removendo '_' e checando 64 bits. */
static int make_int(const char *text, int base)
{
    char clean[128];
    size_t n = 0;
    for (const char *p = text; *p && n < sizeof clean - 1; p++)
        if (*p != '_') clean[n++] = *p;
    clean[n] = '\0';

    errno = 0;
    char *end;
    unsigned long long v = strtoull(clean, &end, base);
    if (errno == ERANGE || *end != '\0' || v > 0x7FFFFFFFFFFFFFFFULL) {
        lex_error(&yylloc, "literal inteiro '%s' excede o tipo int (64 bits)", yytext);
        return TOK_ERROR;
    }
    yylval.ival = (long long) v;
    return INT_LIT;
}

/* Converte o conteúdo entre aspas simples em um código de caractere. */
static int make_char(const char *body, int len)
{
    unsigned char c = (unsigned char) body[0];
    if (c == '\\') {
        switch (body[1]) {
        case 'n':  yylval.cval = '\n'; break;
        case 't':  yylval.cval = '\t'; break;
        case 'r':  yylval.cval = '\r'; break;
        case '0':  yylval.cval = 0;    break;
        case '\\': yylval.cval = '\\'; break;
        case '\'': yylval.cval = '\''; break;
        case '"':  yylval.cval = '"';  break;
        case 'u': {
            unsigned long cp = strtoul(body + 3, NULL, 16);
            if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
                lex_error(&yylloc, "escape unicode inválido em %s", yytext);
                return TOK_ERROR;
            }
            yylval.cval = (int) cp;
            break;
        }
        }
    } else if (len == 1) {
        yylval.cval = c;
    } else {                      /* decodifica UTF-8 de 2 a 4 bytes */
        int cp = c & (len == 2 ? 0x1F : len == 3 ? 0x0F : 0x07);
        for (int i = 1; i < len; i++)
            cp = (cp << 6) | (body[i] & 0x3F);
        yylval.cval = cp;
    }
    return CHAR_LIT;
}

const char *token_name(int kind)
{
    switch (kind) {
    case TOK_EOF:        return "EOF";
    case KW_VAL:         return "VAL";
    case KW_VAR:         return "VAR";
    case KW_DEF:         return "DEF";
    case KW_PUB:         return "PUB";
    case KW_RETURN:      return "RETURN";
    case KW_IF:          return "IF";
    case KW_ELSE:        return "ELSE";
    case KW_FOR:         return "FOR";
    case KW_FOREACH:     return "FOREACH";
    case KW_IN:          return "IN";
    case KW_MATCH:       return "MATCH";
    case KW_STRUCT:      return "STRUCT";
    case KW_ENUM:        return "ENUM";
    case KW_IMPORT:      return "IMPORT";
    case KW_TRUE:        return "TRUE";
    case KW_FALSE:       return "FALSE";
    case KW_INT:         return "T_INT";
    case KW_FLOAT:       return "T_FLOAT";
    case KW_DOUBLE:      return "T_DOUBLE";
    case KW_DECIMAL:     return "T_DECIMAL";
    case KW_BOOL:        return "T_BOOL";
    case KW_CHAR:        return "T_CHAR";
    case KW_STR:         return "T_STR";
    case IDENT:          return "IDENT";
    case INT_LIT:        return "INT_LIT";
    case FLOAT_LIT:      return "FLOAT_LIT";
    case STRING_LIT:     return "STRING_LIT";
    case CHAR_LIT:       return "CHAR_LIT";
    case OP_PLUS:        return "PLUS";
    case OP_MINUS:       return "MINUS";
    case OP_STAR:        return "STAR";
    case OP_SLASH:       return "SLASH";
    case OP_PERCENT:     return "PERCENT";
    case OP_EQ:          return "EQ";
    case OP_NE:          return "NE";
    case OP_LT:          return "LT";
    case OP_LE:          return "LE";
    case OP_GT:          return "GT";
    case OP_GE:          return "GE";
    case OP_AND:         return "AND";
    case OP_OR:          return "OR";
    case OP_NOT:         return "NOT";
    case OP_ASSIGN:      return "ASSIGN";
    case OP_ARROW:       return "ARROW";
    case OP_FAT_ARROW:   return "FAT_ARROW";
    case OP_RANGE:       return "RANGE";
    case OP_RANGE_INCL:  return "RANGE_INCL";
    case OP_SCOPE:       return "SCOPE";
    case OP_DOT:         return "DOT";
    case OP_QUESTION:    return "QUESTION";
    case LPAREN:         return "LPAREN";
    case RPAREN:         return "RPAREN";
    case LBRACE:         return "LBRACE";
    case RBRACE:         return "RBRACE";
    case LBRACKET:       return "LBRACKET";
    case RBRACKET:       return "RBRACKET";
    case COMMA:          return "COMMA";
    case SEMICOLON:      return "SEMICOLON";
    case COLON:          return "COLON";
    case AT:             return "AT";
    case TOK_ERROR:      return "ERROR";
    default:             return "?";
    }
}
