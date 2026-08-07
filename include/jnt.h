/* joints — parsing as algebra, over a C ABI.
 *
 * One library, every language: open a BANK (a .folio holding one grammar, a
 * codex holding several, or a tree-sitter grammar.json pressed on open), lend
 * a PARSER for one language out of it, and get TREES back. A grammar here is
 * data, not a generated C program, so there is no shared library per
 * language and no ABI window — one libjnt plus one file is the whole stack.
 *
 * Lifetimes are a strict order the host keeps: a tree borrows its parser,
 * a parser borrows its bank. Free trees, then parsers, then the bank. A
 * parser owns the scratch its parses run in, so use one per thread — two
 * parsers on two threads are fine, one parser on two is not.
 *
 * Strings cross two ways, on purpose. Titles, node names, fields, and
 * renders are borrowed POINTER + LENGTH views into the handle that answered
 * (a folio's names are mmap-ed bytes; copying per call is the allocation
 * this format exists to avoid) and are NOT NUL-terminated unless said so.
 * Only jnt_version, jnt_last_error, and jnt_tree_sexp are NUL-terminated.
 *
 * Every entry returns a status instead of aborting, so a malformed file or a
 * wrong language never terminates the host. On a negative status,
 * jnt_last_error() holds the sentence the joints CLI would have printed —
 * per thread, valid until that thread's next jnt_* call. */
#ifndef JNT_H
#define JNT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── versions ────────────────────────────────────────────────────── */

/* C-ABI version for this library; bumps only on a breaking layout or
 * signature change, so a consumer can reject a mismatched shared object. */
uint32_t jnt_abi_version(void);

/* The package semver, NUL-terminated, static-lifetime, never NULL. */
const char *jnt_version(void);

/* ── status vocabulary ───────────────────────────────────────────── */

/* 0 is success; each negative names whose fault the refusal is, because a
 * host retries an IO and never a FORMAT. */
#define JNT_OK 0
#define JNT_INVALID (-1)  /* NULL argument, or a handle misused            */
#define JNT_IO (-2)       /* the file could not be read at all             */
#define JNT_FORMAT (-3)   /* read, and not a folio/codex this build loads  */
#define JNT_LANGUAGE (-4) /* language not in the bank, or several unnamed  */
#define JNT_GRAMMAR (-5)  /* grammar.json refused by the importer or press */
#define JNT_NOMEM (-6)

/* The sentence behind the last failing call on THIS thread, or "" after a
 * success. NUL-terminated, valid until this thread's next jnt_* call.
 * Reading does not consume. */
const char *jnt_last_error(void);

/* ── the bank: a file of languages ───────────────────────────────── */

typedef struct jnt_bank jnt_bank;
typedef struct jnt_parser jnt_parser;
typedef struct jnt_tree jnt_tree;

/* Open path — a folio, a codex, or a tree-sitter grammar.json — and write
 * the handle to *out. The mapped two cost milliseconds; the JSON is imported
 * and pressed here, which is the slow path minting a folio exists to end. */
int32_t jnt_open(const char *path, jnt_bank **out);

/* Release a bank. Every parser lent from it must be freed first. */
void jnt_close(jnt_bank *bank);

/* How many languages the bank holds (1 for a folio or grammar.json). */
uint32_t jnt_bank_count(const jnt_bank *bank);

/* The name of language i, borrowed pointer + length; NULL past the end. */
const char *jnt_bank_title(const jnt_bank *bank, uint32_t i, size_t *len);

/* ── the parser: one language, standing ──────────────────────────── */

/* Bind `language` out of the bank. NULL means "the obvious one", which
 * exists only when the bank holds exactly one; a codex of several is refused
 * with its roster in jnt_last_error, never guessed at — a python file parsed
 * with the rust tables hands back a tree that looks fine and is wrong. */
int32_t jnt_parser_new(jnt_bank *bank, const char *language, jnt_parser **out);

/* Release a parser. Trees lent from it must be freed first. */
void jnt_parser_free(jnt_parser *parser);

/* The grammar this parser parses, borrowed pointer + length. Never NULL. */
const char *jnt_parser_language(const jnt_parser *parser, size_t *len);

/* Externally scanned terminals no lexer rule can produce. Zero for most
 * grammars; nonzero is the number to read before blaming a stopped parse. */
uint32_t jnt_parser_blind(const jnt_parser *parser);

/* ── the parse ───────────────────────────────────────────────────── */

/* Parse text[0..len]. A tree comes back on EVERY 0 return, accepted or not —
 * a partial tree plus the reason beats an error with no prefix — and
 * jnt_tree_stop says which this is. text may be freed once this returns. */
int32_t jnt_parse(jnt_parser *parser, const char *text, size_t len, jnt_tree **out);

/* Release a tree and every render lent from it. */
void jnt_tree_free(jnt_tree *tree);

/* How the parse ended. Only ACCEPTED is a whole tree; the rest name the
 * exact byte or token that ended it. */
#define JNT_ACCEPTED 0
#define JNT_STRAY 1      /* no terminal lexes at this byte              */
#define JNT_UNEXPECTED 2 /* a token lexed that no fold makes legal here */
#define JNT_TRUNCATED 3  /* input ended before the start symbol did     */

int32_t jnt_tree_stop(const jnt_tree *tree);

/* The byte the stop names, for STRAY and UNEXPECTED; 0 otherwise. */
uint32_t jnt_tree_stop_at(const jnt_tree *tree);

/* The terminal an UNEXPECTED stop refused, borrowed pointer + length;
 * NULL for the other three stops. */
const char *jnt_tree_stop_word(const jnt_tree *tree, size_t *len);

/* The repairs: deletions past a refusal, the bytes they walked over, and the
 * terminals supplied that the author did not write. Zero mends is a parse
 * that reached its stop and ended there. */
uint32_t jnt_tree_mends(const jnt_tree *tree);
uint32_t jnt_tree_skipped(const jnt_tree *tree);
uint32_t jnt_tree_supplied(const jnt_tree *tree);

/* Whether the arena is a tree at all — every node reached exactly once,
 * children in source order and inside their parents. Surveyed on every
 * parse, so this is a report, never a fresh walk. 1 sound, 0 not. */
int32_t jnt_tree_sound(const jnt_tree *tree);

/* The whole forest as an s-expression, one root per line, in tree-sitter's
 * own spelling. `all` nonzero keeps the anonymous nodes. Borrowed from the
 * tree, rendered once and cached, NUL-terminated; NULL only on OOM. */
const char *jnt_tree_sexp(jnt_tree *tree, int32_t all, size_t *len);

/* ── the nodes ───────────────────────────────────────────────────── */

/* A node is a uint32_t ref into the tree it came from; JNT_NONE is the
 * answer that is not a node. Every accessor bounds-checks, so a stale or
 * invented ref reads as absence rather than as memory. */
#define JNT_NONE UINT32_MAX

/* The nodes standing at the top when the parse stopped: 1 for a whole
 * parse, a forest for one that stopped early. */
uint32_t jnt_tree_roots(const jnt_tree *tree);
uint32_t jnt_tree_root(const jnt_tree *tree, uint32_t i);

/* The node's name in the grammar's own spelling; NULL for a non-node. */
const char *jnt_node_name(const jnt_tree *tree, uint32_t ref, size_t *len);

/* 1 when a query could match this node by name; 0 for a node spelled as
 * itself ("+") and for a non-node. */
int32_t jnt_node_named(const jnt_tree *tree, uint32_t ref);

/* The byte span this node covers, [start, end). */
uint32_t jnt_node_start(const jnt_tree *tree, uint32_t ref);
uint32_t jnt_node_end(const jnt_tree *tree, uint32_t ref);

/* Children — all of them, anonymous included, which is the tree a query
 * actually walks. jnt_node_kid answers JNT_NONE past the end. */
uint32_t jnt_node_kids(const jnt_tree *tree, uint32_t ref);
uint32_t jnt_node_kid(const jnt_tree *tree, uint32_t ref, uint32_t i);

/* The field this node is filed under in its parent; NULL when unfiled. */
const char *jnt_node_field(const jnt_tree *tree, uint32_t ref, size_t *len);

#ifdef __cplusplus
}
#endif

#endif /* JNT_H */
