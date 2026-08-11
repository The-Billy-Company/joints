/* joints — parsing as algebra, over a C ABI.
 *
 * One library, every language: open a BANK (a .folio holding one grammar, a
 * codex holding several, or a tree-sitter grammar.json pressed on open), lend
 * a PARSER for one language out of it, and get TREES back. A grammar here is
 * data, not a generated C program, so there is no shared library per
 * language and no ABI window — one libjnt plus one file is the whole stack.
 *
 * Two doors: jnt_parse for a file read once, and a WEAVE for one held open
 * across keystrokes, which is the door incremental parsing exists behind.
 * Both answer through the same jnt_tree and the same node vocabulary.
 *
 * Lifetimes are a strict order the host keeps: a tree or a weave borrows
 * its parser, a parser borrows its bank. Free trees and weaves, then
 * parsers, then the bank. A parser owns the scratch its parses run in, so
 * use one per thread — two parsers on two threads are fine, one parser on
 * two is not.
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
 * children in source order and inside their parents. 1 sound, 0 not,
 * JNT_NOMEM when the walk could not be afforded, because "cannot tell" and
 * "not a tree" are different answers. Walked on the first ask and kept. */
int32_t jnt_tree_sound(jnt_tree *tree);

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

/* ── the neighbourhood ───────────────────────────────────────────── */

/* There is no cursor type here and that is not an omission. tree-sitter
 * ships one because its TSNode is a struct whose parent costs a walk from
 * the root; here a node is a uint32_t index and its parent is a field read,
 * so a cursor would hold the two integers you are already holding. These
 * are what one would have been made of. */

/* Whoever holds this node; JNT_NONE for a root and for a non-node. The top
 * of the tree is a RUN, not a node: a parse that stopped early hands back
 * every subtree it finished, so those are siblings of each other and
 * children of nothing. */
uint32_t jnt_node_parent(const jnt_tree *tree, uint32_t ref);

/* The neighbours in the run holding this node, anonymous ones included. */
uint32_t jnt_node_next(const jnt_tree *tree, uint32_t ref);
uint32_t jnt_node_prev(const jnt_tree *tree, uint32_t ref);

/* The neighbours a query could match by name. A comment is one of them —
 * being an extra does not exempt it, which is tree-sitter's answer too. */
uint32_t jnt_node_next_named(const jnt_tree *tree, uint32_t ref);
uint32_t jnt_node_prev_named(const jnt_tree *tree, uint32_t ref);

/* The child filed under field[0..len], or JNT_NONE. The first such child,
 * since a production may file two steps under one name; an extra is never
 * the answer. Pass the length — this crosses like every other string. */
uint32_t jnt_node_by_field(const jnt_tree *tree, uint32_t ref, const char *field, size_t len);

/* Parent hops to a root, so every root is 0. */
uint32_t jnt_node_depth(const jnt_tree *tree, uint32_t ref);

/* The deepest node covering [from, to), or JNT_NONE when no root does —
 * highlight the viewport, not the file. Absence is a real answer: a range
 * inside a stretch a repair walked past is covered by nothing. */
uint32_t jnt_node_covering(const jnt_tree *tree, uint32_t from, uint32_t to);

/* Nodes under this one, counting it. 0 for a non-node, and 0 when the walk
 * could not be afforded — a real subtree is at least itself. */
uint32_t jnt_node_spread(const jnt_tree *tree, uint32_t ref);

/* ── the weave: one file, held open ──────────────────────────────── */

/* jnt_parse answers "what is this file". A weave answers "what is it now,
 * given that it was that a moment ago" — the question an editor asks a
 * thousand times an hour, and the only one an incremental parser is for.
 *
 * The handle is the FILE, not the parse. jnt_weave_tree lends back a tree
 * the weave owns and refreshes in place: the pointer stays valid and stays
 * correct across every edit, and must not be freed. What does not survive
 * an edit is a uint32_t node ref taken before it, because the arena those
 * index into is rebuilt. Refs are per parse; the handle is per file.
 *
 * A weave borrows its parser, which borrows its bank. Free weaves, then
 * parsers, then the bank. */

typedef struct jnt_weave jnt_weave;

/* How far the re-mint window widens when an edit destabilises the state a
 * leaf begins in. A cost decision and never a correctness one — all three
 * derive the same leaves and differ only in how many they derive again. */
#define JNT_POLICY_PROVE 0 /* stop when the algebra says so (the default) */
#define JNT_POLICY_SNAP 1  /* stop on a matching entry state              */
#define JNT_POLICY_WHOLE 2 /* re-derive everything past the edit          */

/* What the last warp or amend cost, in the units the incremental claim is
 * stated in. One struct rather than eleven calls, because a status line
 * wants the whole row or none of it. */
typedef struct {
  uint32_t leaves;  /* leaves the spine holds over the whole file        */
  uint32_t height;  /* what a one-for-one splice costs in compositions   */
  uint32_t at;      /* where the re-mint window opened                   */
  uint32_t minted;  /* leaves re-derived                                 */
  uint32_t kept;    /* leaves whose old elements stood untouched         */
  uint32_t lifts;   /* subtrees lifted whole out of the previous tree    */
  uint32_t skipped; /* bytes under those subtrees                        */
  uint32_t carried; /* nodes copied to carry them over                   */
  uint32_t nodes;   /* nodes in the tree that came out                   */
  uint32_t read;    /* stream entries this run moved over                */
  uint32_t stood;   /* the byte the parse began at; 0 is from the ground */
} jnt_cost;

/* Hold a file open on this parser. */
int32_t jnt_weave_new(jnt_parser *parser, jnt_weave **out);

/* Release a weave. The tree it lent dies with it; do not free that first. */
void jnt_weave_free(jnt_weave *weave);

/* Read text[0..len] in cold — what every later edit is measured against.
 * Calling it twice reads a SECOND file: everything the weave was holding
 * about the first describes a document that is gone, and is stood down. */
int32_t jnt_weave_warp(jnt_weave *weave, const char *text, size_t len);

/* Replace [from, to) with insert[0..len] and maintain both halves over the
 * result. The offsets address the file AS IT STANDS, so a run of these is a
 * session and not a set of patches: the second one's offsets are the first
 * one's result. An empty insert is a deletion, from == to an insertion. A
 * span outside the file is JNT_INVALID and leaves the file untouched. */
int32_t jnt_weave_amend(jnt_weave *weave, uint32_t from, uint32_t to, const char *insert, size_t len);

/* The tree as the file stands. Borrowed, stable across edits, NOT to be
 * freed (jnt_tree_free on it is a no-op). NULL until a warp. */
jnt_tree *jnt_weave_tree(jnt_weave *weave);

/* How many bytes the file holds, which is what the next amend is checked
 * against. */
size_t jnt_weave_len(const jnt_weave *weave);

/* Set the re-mint policy, from the next amend onward. */
int32_t jnt_weave_policy(jnt_weave *weave, int32_t policy);

/* What the last warp or amend cost, written into *out. */
int32_t jnt_weave_cost(const jnt_weave *weave, jnt_cost *out);

#ifdef __cplusplus
}
#endif

#endif /* JNT_H */
